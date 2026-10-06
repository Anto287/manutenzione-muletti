-- All fixtures, fake Gmail credentials, jobs and net requests are rolled back.
begin;
insert into private.admin_emails(email) values('deadline-test@gmail.com');
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
 ('deade001-0000-4000-8000-000000000001','deadline-test@gmail.com',now(),'{}','{}'),
 ('deade001-0000-4000-8000-000000000002','other-deadline@liftcare.invalid',now(),'{}','{}'),
 ('deade001-0000-4000-8000-000000000003','pending-deadline@liftcare.invalid',now(),'{}','{"approved":true}');
insert into auth.sessions(id,user_id) values
 ('deade002-0000-4000-8000-000000000001','deade001-0000-4000-8000-000000000001'),
 ('deade002-0000-4000-8000-000000000002','deade001-0000-4000-8000-000000000002'),
 ('deade002-0000-4000-8000-000000000003','deade001-0000-4000-8000-000000000003');
update private.app_members set approved=true where user_id='deade001-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"deade001-0000-4000-8000-000000000001","session_id":"deade002-0000-4000-8000-000000000001"}',true);
insert into public.machines(id,name,type,unit,reading) values('deadline-car','Deadline test','car','km',100);
insert into public.vehicle_deadlines(id,machine_id,kind,due_date) values
 ('revision-test','deadline-car','revision',(now() at time zone 'Europe/Rome')::date+7),
 ('tax-test','deadline-car','tax',(now() at time zone 'Europe/Rome')::date),
 ('insurance-test','deadline-car','insurance',(now() at time zone 'Europe/Rome')::date+31);
do $$begin
 if (public.reminder_status()->>'recipient')<>'deadline-test@gmail.com' then raise exception 'Wrong owner destination';end if;
 begin perform public.configure_gmail('normal-password');raise exception 'Invalid app password accepted';exception when raise_exception then if sqlerrm='Invalid app password accepted' then raise;end if;end;
 perform public.configure_gmail('abcdefghijklmnop');
 if not (public.email_status()->>'gmail_configured')::boolean then raise exception 'Gmail status missing';end if;
 begin update public.vehicle_deadlines set owner_id='deade001-0000-4000-8000-000000000002' where id='revision-test';raise exception 'Owner changed';exception when raise_exception then if sqlerrm='Owner changed' then raise;end if;end;
 begin perform public.claim_deadline_jobs('fake');raise exception 'Worker API exposed';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"deade001-0000-4000-8000-000000000002","session_id":"deade002-0000-4000-8000-000000000002"}',true);
do $$begin
 if exists(select 1 from public.vehicle_deadlines) then raise exception 'Cross-owner deadline read';end if;
 begin insert into public.vehicle_deadlines(id,machine_id,kind,due_date) values('cross','deadline-car','revision',current_date);raise exception 'Cross-owner deadline write';exception when foreign_key_violation then null;end;
 begin perform public.configure_gmail('abcdefghijklmnop');raise exception 'Nonadmin SMTP config allowed';exception when sqlstate 'PT403' then null;end;
end$$;
insert into public.machines(id,name,type,unit,reading) values('deadline-car2','Owner 2','car','km',100);
insert into public.vehicle_deadlines(id,machine_id,kind,due_date) values('other-insurance','deadline-car2','insurance',(now() at time zone 'Europe/Rome')::date+1);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"deade001-0000-4000-8000-000000000003","session_id":"deade002-0000-4000-8000-000000000003"}',true);
do $$begin
 if exists(select 1 from public.vehicle_deadlines) then raise exception 'Pending read allowed';end if;
 begin perform public.reminder_status();raise exception 'Pending status allowed';exception when sqlstate 'PT401' then null;end;
end$$;
reset role;
do $$declare token text;jobs jsonb;j bigint;begin
 if (select count(*) from private.reminder_candidates((now() at time zone 'Europe/Rome')::date) where owner_id in ('deade001-0000-4000-8000-000000000001','deade001-0000-4000-8000-000000000002'))<>3 then raise exception 'Wrong reminder window';end if;
 if extract(hour from now() at time zone 'Europe/Rome')>=9 then
  perform private.prepare_deadline_reminders();perform private.prepare_deadline_reminders();
  if (select count(*) from private.reminder_outbox where owner_id='deade001-0000-4000-8000-000000000001')<>1 then raise exception 'Digest duplication';end if;
  if (select jsonb_array_length(items) from private.reminder_outbox where owner_id='deade001-0000-4000-8000-000000000001')<>2 then raise exception 'Digest grouping failed';end if;
  -- Renew one date and opt out the other owner before claiming. They must not receive stale jobs.
  update public.vehicle_deadlines set due_date=due_date+365 where id='revision-test' and owner_id='deade001-0000-4000-8000-000000000001';
  insert into private.reminder_preferences(owner_id,enabled) values('deade001-0000-4000-8000-000000000002',false);
  select decrypted_secret into token from vault.decrypted_secrets where name='liftcare_email_job_token';
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  jobs:=public.claim_registration_email('new-account@liftcare.invalid');
  if jobs->>'transport'<>'gmail' or not (jobs->>'eligible')::boolean then raise exception 'External Gmail confirmation unsupported';end if;
  begin perform public.claim_registration_email('new-account@liftcare.invalid');raise exception 'Registration rate limit ignored';exception when sqlstate 'PT429' then null;end;
  perform public.check_deadline_worker(token);
  jobs:=public.claim_deadline_jobs(token);
  if exists(select 1 from jsonb_array_elements(jobs->'jobs') x where x->>'to'='other-deadline@liftcare.invalid') then raise exception 'Opt-out ignored';end if;
  if (select jsonb_array_length(x->'items') from jsonb_array_elements(jobs->'jobs') x where x->>'to'='deadline-test@gmail.com')<>1 then raise exception 'Renewal stale email';end if;
  select (x->>'id')::bigint into j from jsonb_array_elements(jobs->'jobs') x where x->>'to'='deadline-test@gmail.com';
  perform public.finish_deadline_job(token,j,'sent',null,'mock-provider-id');
  if (select state from private.reminder_outbox where id=j)<>'sent' then raise exception 'SMTP receipt not recorded';end if;
  insert into private.gmail_delivery_attempts(kind) select 'registration' from generate_series(1,50);
  begin perform public.claim_registration_email('budget-test@liftcare.invalid');raise exception 'Shared Gmail quota ignored';exception when sqlstate 'PT429' then null;end;
  if not (public.claim_deadline_jobs(token)->>'budget_blocked')::boolean then raise exception 'Reminder shared quota ignored';end if;
  perform private.prepare_deadline_reminders();
  if exists(select 1 from private.reminder_candidates((now() at time zone 'Europe/Rome')::date) where owner_id='deade001-0000-4000-8000-000000000001') then raise exception 'Repeated reminder';end if;
 end if;
end$$;
-- Legacy and new archive imports remain transactional and owner scoped.
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"deade001-0000-4000-8000-000000000002","session_id":"deade002-0000-4000-8000-000000000002"}',true);
delete from public.vehicle_deadlines;delete from public.machines;
select public.import_archive('{"version":2,"vehicles":[{"id":"import-car","name":"Imported","type":"car","model":"Test","serial":"","plate":"","power":"Diesel","unit":"km","reading":0}],"tasks":[],"history":[],"deadlines":[{"id":"import-date","vehicleId":"import-car","kind":"tax","dueDate":"2027-01-01","notify":true,"notes":""}],"emailNotifications":false}');
do $$begin if (select count(*) from public.vehicle_deadlines)<>1 or (public.reminder_status()->>'enabled')::boolean then raise exception 'Archive import failed';end if;end$$;
reset role;
rollback;
select 'Deadlines: owner isolation, pending denial, Gmail vault config, grouped reminders, deduplication, renewal cancellation, opt-out, SMTP receipt and backup import passed. All fixtures rolled back.' as result;
