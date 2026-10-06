begin;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create table private.email_config(singleton boolean primary key default true check(singleton),key_id uuid not null,from_email text not null default 'LiftCare <onboarding@resend.dev>');
alter table private.email_config enable row level security;
revoke all on private.email_config from public,anon,authenticated;
alter table private.access_email_outbox add column attempts integer not null default 0,add column attempted_at timestamptz,add column last_error text;
-- The webhook credential is generated on the server and never included in source control.
do $$begin
 if not exists(select 1 from vault.secrets where name='liftcare_email_job_token') then
 perform vault.create_secret(gen_random_uuid()::text||gen_random_uuid()::text,'liftcare_email_job_token','LiftCare private email worker authentication');
 end if;
end$$;
create function private.enqueue_emails() returns void language plpgsql security definer set search_path='' as $$
declare token text;
begin
 if not exists(select 1 from private.email_config) or not exists(select 1 from private.access_email_outbox where sent_at is null and attempts<5 and (attempted_at is null or attempted_at<now()-interval '15 minutes')) then return; end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='liftcare_email_job_token';
 perform net.http_post(url:='https://tkugxpgljwcnndjsmhjq.supabase.co/functions/v1/access-email',body:='{}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-liftcare-job',token),timeout_milliseconds:=10000);
end$$;
revoke all on function private.enqueue_emails() from public,anon,authenticated;
create function private.notify_new_request() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.enqueue_emails();return new;end$$;
revoke all on function private.notify_new_request() from public,anon,authenticated;
create trigger access_email_new_request after insert on private.access_email_outbox for each statement execute function private.notify_new_request();
create function private.configure_email(resend_key text,sender text) returns void language plpgsql security definer set search_path='' as $$
declare key_uuid uuid;
begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin'; end if;
 if length(resend_key)<15 or resend_key !~ '^re_' or length(resend_key)>200 then raise exception 'Chiave Resend non valida'; end if;
 if sender is null or length(sender)>200 or sender !~ '@' or sender ~ '[\r\n]' then raise exception 'Mittente non valido'; end if;
 select key_id into key_uuid from private.email_config where singleton;
 if key_uuid is null then key_uuid:=vault.create_secret(resend_key,'liftcare_resend_key','LiftCare notification email key');
 else perform vault.update_secret(key_uuid,resend_key); end if;
 insert into private.email_config(singleton,key_id,from_email) values(true,key_uuid,sender) on conflict(singleton) do update set from_email=excluded.from_email;
 update private.access_email_outbox set attempts=0,attempted_at=null,last_error=null where sent_at is null;
 perform private.enqueue_emails();
end$$;
create function private.email_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin'; end if;
 return jsonb_build_object('configured',exists(select 1 from private.email_config),'sender',(select from_email from private.email_config),'recipient',(select email from private.admin_emails order by email limit 1),'pending',(select count(*) from private.access_email_outbox where sent_at is null),'sent',(select count(*) from private.access_email_outbox where sent_at is not null),'failed',(select count(*) from private.access_email_outbox where sent_at is null and attempts>=5));
end$$;
revoke all on function private.configure_email(text,text),private.email_status() from public,anon;
grant execute on function private.configure_email(text,text),private.email_status() to authenticated;
create function public.configure_email(resend_key text,sender text default 'LiftCare <onboarding@resend.dev>') returns void language sql security invoker set search_path='' as $$select private.configure_email(resend_key,sender);$$;
create function public.email_status() returns jsonb language sql security invoker set search_path='' as $$select private.email_status();$$;
revoke all on function public.configure_email(text,text),public.email_status() from public,anon;
grant execute on function public.configure_email(text,text),public.email_status() to authenticated;
-- Only the Edge Function service role can access this data; browser users cannot read the key.
create function private.claim_email_jobs(job_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb; config private.email_config; token text; key_value text;
begin
 if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','')<>'service_role' then raise sqlstate 'PT401' using message='Accesso richiesto'; end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='liftcare_email_job_token';
 if job_token is null or token is null or job_token<>token then raise sqlstate 'PT401' using message='Accesso richiesto'; end if;
 select * into config from private.email_config;
 if not found then return '{"configured":false,"jobs":[]}'::jsonb; end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-email-budget',0));
 -- Conservative per-day/month caps below the Free allowance, including failed attempts.
 if (select coalesce(sum(attempts),0) from private.access_email_outbox where attempted_at>=date_trunc('day',now()))>=80 or
 (select coalesce(sum(attempts),0) from private.access_email_outbox where attempted_at>=date_trunc('month',now()))>=2500 then return '{"configured":true,"jobs":[],"budget_blocked":true}'::jsonb; end if;
 with picked as (select id from private.access_email_outbox where sent_at is null and attempts<5 and (attempted_at is null or attempted_at<now()-interval '15 minutes') order by created_at for update skip locked limit 10), updated as (update private.access_email_outbox o set attempts=o.attempts+1,attempted_at=now() from picked where o.id=picked.id returning o.id,o.email,o.user_id)
 select coalesce(jsonb_agg(to_jsonb(updated)),'[]'::jsonb) into jobs from updated;
 select decrypted_secret into key_value from vault.decrypted_secrets where id=config.key_id;
 return jsonb_build_object('configured',true,'key',key_value,'from',config.from_email,'to',(select email from private.admin_emails order by email limit 1),'jobs',jobs);
end$$;
create function private.finish_email_job(job_token text,job_id bigint,succeeded boolean,error_code text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','')<>'service_role' or not exists(select 1 from vault.decrypted_secrets where name='liftcare_email_job_token' and decrypted_secret=job_token) then raise sqlstate 'PT401' using message='Accesso richiesto'; end if;
 update private.access_email_outbox set sent_at=case when succeeded then now() else null end,last_error=case when succeeded then null else left(error_code,100) end where id=job_id and sent_at is null;
end$$;
revoke all on function private.claim_email_jobs(text),private.finish_email_job(text,bigint,boolean,text) from public,anon,authenticated;
grant execute on function private.claim_email_jobs(text),private.finish_email_job(text,bigint,boolean,text) to service_role;
create function public.claim_email_jobs(job_token text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_email_jobs(job_token);$$;
create function public.finish_email_job(job_token text,job_id bigint,succeeded boolean,error_code text default null) returns void language sql security invoker set search_path='' as $$select private.finish_email_job(job_token,job_id,succeeded,error_code);$$;
revoke all on function public.claim_email_jobs(text),public.finish_email_job(text,bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_email_jobs(text),public.finish_email_job(text,bigint,boolean,text) to service_role;
grant usage on schema private to service_role;
select cron.schedule('liftcare-email-retry','0 * * * *','select private.enqueue_emails()');
notify pgrst,'reload schema';
commit;
