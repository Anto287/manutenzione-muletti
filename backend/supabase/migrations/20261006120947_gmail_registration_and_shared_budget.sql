begin;
create table private.gmail_delivery_attempts(id bigint generated always as identity primary key,kind text not null check(kind in ('registration','reminder')),attempted_at timestamptz not null default now());
create index gmail_attempts_time on private.gmail_delivery_attempts(attempted_at);
alter table private.gmail_delivery_attempts enable row level security;
revoke all on private.gmail_delivery_attempts from public,anon,authenticated;
-- One shared 50-attempt budget per rolling 24 hours across confirmations and reminders.
alter function private.claim_registration_email(text) rename to claim_registration_email_resend;
create function private.claim_registration_email(recipient text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.gmail_config; state private.registration_email_limits; email_value text:=lower(trim(recipient));password_value text;
begin
 if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','')<>'service_role' then raise sqlstate 'PT401' using message='Accesso richiesto';end if;
 select * into cfg from private.gmail_config;
 if not found then return private.claim_registration_email_resend(recipient);end if;
 if email_value is null or length(email_value)>254 or email_value !~ '^[^[:space:]@,;<>]+@[^[:space:]@,;<>]+[.][^[:space:]@,;<>]+$' then raise exception 'Email non valida';end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-gmail-budget',0));
 if (select count(*) from private.gmail_delivery_attempts where attempted_at>now()-interval '24 hours')>=50 or (select count(*) from private.gmail_delivery_attempts where kind='registration' and attempted_at>now()-interval '24 hours')>=20 then raise sqlstate 'PT429' using message='Limite invii gratuito raggiunto';end if;
 select * into state from private.registration_email_limits where email=email_value;
 if found and (state.last_attempt>now()-interval '60 seconds' or (state.day=current_date and state.attempts>=5)) then raise sqlstate 'PT429' using message='Limite invii';end if;
 insert into private.registration_email_limits(email,day,attempts,last_attempt) values(email_value,current_date,1,now()) on conflict(email) do update set day=current_date,attempts=case when private.registration_email_limits.day=current_date then private.registration_email_limits.attempts+1 else 1 end,last_attempt=now();
 insert into private.gmail_delivery_attempts(kind) values('registration');
 select decrypted_secret into password_value from vault.decrypted_secrets where id=cfg.key_id;
 return jsonb_build_object('eligible',true,'transport','gmail','sender',cfg.email,'password',password_value,'attempt_id',gen_random_uuid());
end$$;
revoke all on function private.claim_registration_email(text),private.claim_registration_email_resend(text) from public,anon,authenticated;
grant execute on function private.claim_registration_email(text) to service_role;
create or replace function public.claim_registration_email(recipient text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_registration_email(recipient);$$;
create or replace function private.claim_deadline_jobs(job_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.gmail_config;secret_value text; jobs jsonb;r private.reminder_outbox; recipient text;live_items jsonb;budget integer;
begin
 perform private.check_reminder_worker(job_token);
 select * into cfg from private.gmail_config;if not found then return '{"configured":false,"jobs":[]}'::jsonb;end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-gmail-budget',0));
 -- A worker crash may happen after SMTP accepted a message. Never blindly resend that lease.
 update private.reminder_outbox set state='uncertain',last_error='smtp_uncertain' where state='sending' and attempted_at<now()-interval '15 minutes';
 budget:=greatest(0,50-(select count(*)::integer from private.gmail_delivery_attempts where attempted_at>now()-interval '24 hours'));
 jobs:='[]';
 for r in select * from private.reminder_outbox where state='pending' and attempts<3 and (attempted_at is null or attempted_at<now()-interval '15 minutes') order by created_at for update skip locked limit least(budget,5) loop
  select u.email into recipient from auth.users u join private.app_members a on a.user_id=u.id and a.approved where u.id=r.owner_id and u.email_confirmed_at is not null;
  live_items:='[]';
  if coalesce((select enabled from private.reminder_preferences where owner_id=r.owner_id),true) then
   select coalesce(jsonb_agg(i),'[]') into live_items from jsonb_array_elements(r.items) i join public.vehicle_deadlines d on d.owner_id=r.owner_id and d.id=i->>'id' and d.due_date=(i->>'date')::date and d.notify;
  end if;
  if recipient is null or (not r.test and jsonb_array_length(live_items)=0) then update private.reminder_outbox set state='cancelled' where id=r.id;continue;end if;
  update private.reminder_outbox set state='sending',attempts=attempts+1,attempted_at=now(),items=live_items where id=r.id;
  insert into private.gmail_delivery_attempts(kind) values('reminder');
  jobs:=jobs||jsonb_build_array(jsonb_build_object('id',r.id,'to',recipient,'items',live_items,'test',r.test));
 end loop;
 select decrypted_secret into secret_value from vault.decrypted_secrets where id=cfg.key_id;
 return jsonb_build_object('configured',true,'email',cfg.email,'password',secret_value,'jobs',jobs,'budget_blocked',budget=0);
end$$;
notify pgrst,'reload schema';
commit;
