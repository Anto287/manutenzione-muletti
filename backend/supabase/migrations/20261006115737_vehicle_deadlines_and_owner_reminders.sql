begin;
create table public.vehicle_deadlines(
 id text not null default gen_random_uuid()::text,owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 machine_id text not null,kind text not null check(kind in ('revision','tax','insurance')),
 due_date date not null check(isfinite(due_date)),notify boolean not null default true,notes text not null default '' check(length(notes)<=1000),
 primary key(owner_id,id),foreign key(owner_id,machine_id) references public.machines(owner_id,id) on delete cascade,
 unique(owner_id,machine_id,kind)
);
create index deadlines_due on public.vehicle_deadlines(due_date) where notify;
alter table public.vehicle_deadlines enable row level security;
revoke all on public.vehicle_deadlines from public,anon,authenticated;
grant select,insert,update,delete on public.vehicle_deadlines to authenticated;
create policy deadlines_owner on public.vehicle_deadlines to authenticated using(owner_id=(select auth.uid()) and (select private.is_approved())) with check(owner_id=(select auth.uid()) and (select private.is_approved()));
create function private.guard_deadline() returns trigger language plpgsql set search_path='' as $$begin
 if new.owner_id<>old.owner_id or new.id<>old.id or new.machine_id<>old.machine_id or new.kind<>old.kind then raise exception 'Mezzo e tipo di scadenza non modificabili';end if;return new;
end$$;
revoke all on function private.guard_deadline() from public,anon,authenticated;
create trigger guard_deadline before update on public.vehicle_deadlines for each row execute function private.guard_deadline();
create table private.reminder_preferences(owner_id uuid primary key references auth.users(id) on delete cascade,enabled boolean not null default true);
create table private.gmail_config(singleton boolean primary key default true check(singleton),email text not null,key_id uuid not null);
create table private.reminder_outbox(
 id bigint generated always as identity primary key,owner_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),test boolean not null default false,items jsonb not null,
 state text not null default 'pending' check(state in ('pending','sending','sent','failed','uncertain','cancelled')),
 attempts integer not null default 0,attempted_at timestamptz,sent_at timestamptz,last_error text,message_id text
);
create index reminder_pending on private.reminder_outbox(created_at) where state='pending';
create table private.deadline_notices(owner_id uuid not null,deadline_id text not null,due_date date not null,stage integer not null,
 job_id bigint not null references private.reminder_outbox(id) on delete cascade,
 primary key(owner_id,deadline_id,due_date,stage),foreign key(owner_id,deadline_id) references public.vehicle_deadlines(owner_id,id) on delete cascade);
alter table private.reminder_preferences enable row level security;
alter table private.gmail_config enable row level security;
alter table private.reminder_outbox enable row level security;
alter table private.deadline_notices enable row level security;
revoke all on private.reminder_preferences,private.gmail_config,private.reminder_outbox,private.deadline_notices from public,anon,authenticated;

create function private.set_reminder_preference(enabled boolean) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.check_access();if enabled is null then raise exception 'Preferenza non valida';end if;
 insert into private.reminder_preferences(owner_id,enabled) values(auth.uid(),enabled) on conflict(owner_id) do update set enabled=excluded.enabled;
end$$;
create function private.reminder_status() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform private.check_access();return jsonb_build_object('enabled',coalesce((select enabled from private.reminder_preferences where owner_id=auth.uid()),true),
 'recipient',(select email from auth.users where id=auth.uid()),'configured',exists(select 1 from private.gmail_config),
 'transport',case when exists(select 1 from private.gmail_config) then 'gmail' when exists(select 1 from private.email_config) then 'resend_test' else 'unconfigured' end,
 'sent',(select count(*) from private.reminder_outbox where owner_id=auth.uid() and state='sent'),
 'pending',(select count(*) from private.reminder_outbox where owner_id=auth.uid() and state in ('pending','sending')),
 'failed',(select count(*) from private.reminder_outbox where owner_id=auth.uid() and state in ('failed','uncertain')),
 'last_error',(select case when last_error='smtp_auth' then 'Gmail non ha accettato la password per app: l’admin deve aggiornarla.' when last_error='smtp_uncertain' then 'Consegna da verificare: nessun reinvio automatico per evitare duplicati.' when state='failed' then 'Invio non riuscito: controlla la configurazione Gmail con l’admin.' else null end from private.reminder_outbox where owner_id=auth.uid() and state in ('failed','uncertain') order by id desc limit 1));
end$$;
create function private.configure_gmail(app_password text) returns void language plpgsql security definer set search_path='' as $$
declare email_address text;password_value text;key_uuid uuid;
begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin';end if;
 select lower(email) into email_address from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if email_address !~ '^[a-z0-9.+_-]+@gmail[.]com$' then raise exception 'Il mittente deve essere l’account Gmail confermato dell’admin';end if;
 password_value:=regexp_replace(app_password,'\s','','g');
 if password_value is null or password_value !~ '^[a-zA-Z0-9]{16}$' then raise exception 'Inserisci la password per app Google di 16 caratteri, non la password dell’account';end if;
 select key_id into key_uuid from private.gmail_config;
 if key_uuid is null then key_uuid:=vault.create_secret(password_value,'liftcare_gmail_app_password','LiftCare Gmail SMTP credential');else perform vault.update_secret(key_uuid,password_value);end if;
 insert into private.gmail_config(singleton,email,key_id) values(true,email_address,key_uuid) on conflict(singleton) do update set email=excluded.email,key_id=excluded.key_id;
 -- A proven authentication rejection cannot have delivered mail. Other failures need explicit review.
 update private.reminder_outbox set state='pending',attempts=0,attempted_at=null,last_error=null where state='failed' and last_error='smtp_auth';
end$$;
create function private.reminder_candidates(p_day date) returns table(owner_id uuid,deadline_id text,stage integer,item jsonb) language sql stable security definer set search_path='' as $$
 select d.owner_id,d.id,s.stage,jsonb_build_object('id',d.id,'vehicle',m.name,'plate',m.plate,'kind',d.kind,'date',d.due_date,'stage',s.stage)
 from public.vehicle_deadlines d join public.machines m on m.owner_id=d.owner_id and m.id=d.machine_id
 join auth.users u on u.id=d.owner_id and u.email_confirmed_at is not null
 join private.app_members a on a.user_id=d.owner_id and a.approved
 left join private.reminder_preferences p on p.owner_id=d.owner_id
 cross join lateral(select case when d.due_date-p_day<=-7 then -7 when d.due_date-p_day<=0 then 0 when d.due_date-p_day<=1 then 1 when d.due_date-p_day<=7 then 7 else 30 end stage) s
 where d.notify and coalesce(p.enabled,true) and d.due_date-p_day<=30
 and not exists(select 1 from private.deadline_notices n where n.owner_id=d.owner_id and n.deadline_id=d.id and n.due_date=d.due_date and n.stage=s.stage);
$$;
revoke all on function private.reminder_candidates(date) from public,anon,authenticated;
create function private.prepare_deadline_reminders() returns integer language plpgsql security definer set search_path='' as $$
declare day date:=(now() at time zone 'Europe/Rome')::date;r record;j bigint;n integer:=0;
begin
 perform pg_advisory_xact_lock(hashtextextended('liftcare-deadline-generation',0));
 if not exists(select 1 from private.gmail_config) or extract(hour from now() at time zone 'Europe/Rome')<9 then return 0;end if;
 for r in select owner_id,jsonb_agg(item order by item->>'date',deadline_id) items from private.reminder_candidates(day) c
 where not exists(select 1 from private.reminder_outbox o where o.owner_id=c.owner_id and not o.test and (o.created_at at time zone 'Europe/Rome')::date=day) group by owner_id loop
  insert into private.reminder_outbox(owner_id,items) values(r.owner_id,r.items) returning id into j;
  insert into private.deadline_notices(owner_id,deadline_id,due_date,stage,job_id) select r.owner_id,i->>'id',(i->>'date')::date,(i->>'stage')::integer,j from jsonb_array_elements(r.items) i;
  n:=n+1;
 end loop;return n;
end$$;
create function private.enqueue_deadline_reminders() returns void language plpgsql security definer set search_path='' as $$declare token text;begin
 perform private.prepare_deadline_reminders();
 if not exists(select 1 from private.gmail_config) or not exists(select 1 from private.reminder_outbox where state='pending' and attempts<3 and (attempted_at is null or attempted_at<now()-interval '15 minutes')) then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='liftcare_email_job_token';
 perform net.http_post(url:='https://tkugxpgljwcnndjsmhjq.supabase.co/functions/v1/deadline-email',body:='{}',headers:=jsonb_build_object('Content-Type','application/json','x-liftcare-job',token),timeout_milliseconds:=10000);
end$$;
revoke all on function private.prepare_deadline_reminders(),private.enqueue_deadline_reminders() from public,anon,authenticated;
create function private.request_reminder_test() returns void language plpgsql security definer set search_path='' as $$begin
 perform private.check_access();
 if not exists(select 1 from private.gmail_config) then raise exception 'Collega Gmail nelle Notifiche email dell’admin';end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-reminder-test-'||auth.uid()::text,0));
 if exists(select 1 from private.reminder_outbox where owner_id=auth.uid() and test and created_at>now()-interval '15 minutes') then raise exception 'Prova già richiesta: attendi 15 minuti';end if;
 insert into private.reminder_outbox(owner_id,test,items) values(auth.uid(),true,'[]');perform private.enqueue_deadline_reminders();
end$$;
create function private.check_reminder_worker(job_token text) returns void language plpgsql security definer set search_path='' as $$begin
 if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','')<>'service_role' or job_token is null or not exists(select 1 from vault.decrypted_secrets where name='liftcare_email_job_token' and decrypted_secret=job_token) then raise sqlstate 'PT401' using message='Accesso richiesto';end if;
end$$;
revoke all on function private.check_reminder_worker(text) from public,anon,authenticated;
create function private.claim_deadline_jobs(job_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.gmail_config;secret_value text; jobs jsonb;r private.reminder_outbox; recipient text;live_items jsonb;budget integer;
begin
 perform private.check_reminder_worker(job_token);
 select * into cfg from private.gmail_config;if not found then return '{"configured":false,"jobs":[]}'::jsonb;end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-reminder-send',0));
 -- A worker crash may happen after SMTP accepted a message. Never blindly resend that lease.
 update private.reminder_outbox set state='uncertain',last_error='smtp_uncertain' where state='sending' and attempted_at<now()-interval '15 minutes';
 budget:=greatest(0,50-(select coalesce(sum(attempts),0)::integer from private.reminder_outbox where attempted_at>=now()-interval '24 hours'));
 jobs:='[]';
 for r in select * from private.reminder_outbox where state='pending' and attempts<3 and (attempted_at is null or attempted_at<now()-interval '15 minutes') order by created_at for update skip locked limit least(budget,5) loop
  select u.email into recipient from auth.users u join private.app_members a on a.user_id=u.id and a.approved where u.id=r.owner_id and u.email_confirmed_at is not null;
  live_items:='[]';
  if coalesce((select enabled from private.reminder_preferences where owner_id=r.owner_id),true) then
   select coalesce(jsonb_agg(i),'[]') into live_items from jsonb_array_elements(r.items) i join public.vehicle_deadlines d on d.owner_id=r.owner_id and d.id=i->>'id' and d.due_date=(i->>'date')::date and d.notify;
  end if;
  if recipient is null or (not r.test and jsonb_array_length(live_items)=0) then update private.reminder_outbox set state='cancelled' where id=r.id;continue;end if;
  update private.reminder_outbox set state='sending',attempts=attempts+1,attempted_at=now(),items=live_items where id=r.id;
  jobs:=jobs||jsonb_build_array(jsonb_build_object('id',r.id,'to',recipient,'items',live_items,'test',r.test));
 end loop;
 select decrypted_secret into secret_value from vault.decrypted_secrets where id=cfg.key_id;
 return jsonb_build_object('configured',true,'email',cfg.email,'password',secret_value,'jobs',jobs,'budget_blocked',budget=0);
end$$;
create function private.finish_deadline_job(job_token text,job_id bigint,outcome text,error_code text default null,provider_id text default null) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.check_reminder_worker(job_token);
 if outcome not in ('sent','failed','uncertain','retry') then raise exception 'Esito non valido';end if;
 update private.reminder_outbox set state=case when outcome='retry' and attempts<3 then 'pending' when outcome='retry' then 'failed' else outcome end,
 sent_at=case when outcome='sent' then now() else null end,last_error=case when outcome='sent' then null else left(error_code,100) end,message_id=left(provider_id,200) where id=job_id and state='sending';
end$$;
revoke all on function private.claim_deadline_jobs(text),private.finish_deadline_job(text,bigint,text,text,text) from public,anon,authenticated;
grant execute on function private.claim_deadline_jobs(text),private.finish_deadline_job(text,bigint,text,text,text) to service_role;
create function public.claim_deadline_jobs(job_token text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_deadline_jobs(job_token);$$;
create function public.finish_deadline_job(job_token text,job_id bigint,outcome text,error_code text default null,provider_id text default null) returns void language sql security invoker set search_path='' as $$select private.finish_deadline_job(job_token,job_id,outcome,error_code,provider_id);$$;
revoke all on function public.claim_deadline_jobs(text),public.finish_deadline_job(text,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.claim_deadline_jobs(text),public.finish_deadline_job(text,bigint,text,text,text) to service_role;
create function public.reminder_status() returns jsonb language sql security invoker set search_path='' as $$select private.reminder_status();$$;
create function public.set_reminder_preference(enabled boolean) returns void language sql security invoker set search_path='' as $$select private.set_reminder_preference(enabled);$$;
create function public.configure_gmail(app_password text) returns void language sql security invoker set search_path='' as $$select private.configure_gmail(app_password);$$;
create function public.request_reminder_test() returns void language sql security invoker set search_path='' as $$select private.request_reminder_test();$$;
revoke all on function public.reminder_status(),public.set_reminder_preference(boolean),public.configure_gmail(text),public.request_reminder_test(),private.reminder_status(),private.set_reminder_preference(boolean),private.configure_gmail(text),private.request_reminder_test() from public,anon;
grant execute on function public.reminder_status(),public.set_reminder_preference(boolean),public.configure_gmail(text),public.request_reminder_test(),private.reminder_status(),private.set_reminder_preference(boolean),private.configure_gmail(text),private.request_reminder_test() to authenticated;
-- Keep the existing registration sender unchanged while exposing only Gmail connection status to admins.
alter function private.email_status() rename to registration_email_status;
create function private.email_status() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin';end if;
 return private.registration_email_status()||jsonb_build_object('gmail_configured',exists(select 1 from private.gmail_config),'gmail_sender',(select email from private.gmail_config));
end$$;
revoke all on function private.email_status() from public,anon;grant execute on function private.email_status() to authenticated;
create or replace function public.email_status() returns jsonb language sql security invoker set search_path='' as $$select private.email_status();$$;
-- Preserve backward compatibility of v2 backups, including optional new fields.
alter function private.import_archive(jsonb) rename to import_archive_base;
create function private.import_archive(archive jsonb) returns void language plpgsql security definer set search_path='' as $$declare d jsonb;begin
 perform private.check_access();perform private.import_archive_base(archive);
 if archive ? 'deadlines' and jsonb_typeof(archive->'deadlines')<>'array' then raise exception 'Scadenze non valide';end if;
 for d in select * from jsonb_array_elements(coalesce(archive->'deadlines','[]')) loop
  insert into public.vehicle_deadlines(owner_id,id,machine_id,kind,due_date,notify,notes) values(auth.uid(),d->>'id',d->>'vehicleId',d->>'kind',(d->>'dueDate')::date,(d->>'notify')::boolean,d->>'notes');
 end loop;
 if archive ? 'emailNotifications' then perform private.set_reminder_preference((archive->>'emailNotifications')::boolean);end if;
end$$;
revoke all on function private.import_archive(jsonb),private.import_archive_base(jsonb) from public,anon;
grant execute on function private.import_archive(jsonb) to authenticated;
create or replace function public.import_archive(archive jsonb) returns void language plpgsql security invoker set search_path='' as $$begin perform private.check_access();perform private.import_archive(archive);end$$;
select cron.schedule('liftcare-deadline-reminders','*/15 * * * *','select private.enqueue_deadline_reminders()');
notify pgrst,'reload schema';
commit;
