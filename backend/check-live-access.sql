-- Run in a transaction against the configured test/production project.
-- All test users, sessions, machines and outbox entries are rolled back.
begin;
insert into private.admin_emails(email) values('admin-test@liftcare.invalid');
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values ('be5e8020-4ae5-41db-ad68-ddddda160101','admin-test@liftcare.invalid',now(),'{}','{}'),
('be5e8020-4ae5-41db-ad68-ddddda160102','pending@liftcare.invalid',now(),'{}','{"approved":true,"is_admin":true}'),
('be5e8020-4ae5-41db-ad68-ddddda160103','other@liftcare.invalid',now(),'{}','{}');
insert into auth.sessions(id,user_id) values
('be5e8020-4ae5-41db-ad68-ddddda161101','be5e8020-4ae5-41db-ad68-ddddda160101'),
('be5e8020-4ae5-41db-ad68-ddddda161102','be5e8020-4ae5-41db-ad68-ddddda160102'),
('be5e8020-4ae5-41db-ad68-ddddda161103','be5e8020-4ae5-41db-ad68-ddddda160103');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"be5e8020-4ae5-41db-ad68-ddddda160101","session_id":"be5e8020-4ae5-41db-ad68-ddddda161101"}',true);
do $$begin
 if not (public.access_status()->>'is_admin')::boolean then raise exception 'Admin bootstrap failed'; end if;
 perform private.api_pre_request();
end$$;
insert into public.machines(id,name,type,unit,reading) values('live-test','Test rollback','tractor','h',100);
insert into public.maintenance_plans(id,machine_id,name,interval,last_reading,last_date) values('live-plan','live-test','Filtro gasolio',250,100,'2026-01-01');
select public.record_service('live-test',array['live-plan'],'2026-01-02',110,10,'Test','Test rollback');
do $$begin
 if (select reading from public.machines where id='live-test')<>110 then raise exception 'Transaction failed';end if;
 if public.photo_usage()->>'used_bytes' is null then raise exception 'Usage failed';end if;
 if public.photo_inventory() is null then raise exception 'Inventory failed';end if;
 perform public.set_user_approval('be5e8020-4ae5-41db-ad68-ddddda160103',true);
end$$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"be5e8020-4ae5-41db-ad68-ddddda160102","session_id":"be5e8020-4ae5-41db-ad68-ddddda161102","user_metadata":{"approved":true,"is_admin":true}}',true);
do $$begin
 if (public.access_status()->>'approved')::boolean then raise exception 'User metadata granted approval'; end if;
 begin perform private.api_pre_request();raise exception 'Pending allowed';exception when sqlstate 'PT401' then null;end;
 begin perform public.photo_usage();raise exception 'Pending photos allowed';exception when sqlstate 'PT401' then null;end;
 begin perform public.set_user_approval('be5e8020-4ae5-41db-ad68-ddddda160102',true);raise exception 'Self-approval allowed';exception when sqlstate 'PT403' then null;end;
 if exists(select 1 from public.machines) then raise exception 'RLS leaked data';end if;
end$$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"be5e8020-4ae5-41db-ad68-ddddda160103","session_id":"be5e8020-4ae5-41db-ad68-ddddda161103"}',true);
do $$begin
 perform private.api_pre_request();
 if exists(select 1 from public.machines) then raise exception 'Owner isolation failed';end if;
 begin perform public.record_service('live-test',array['live-plan'],'2026-01-02',120);raise exception 'Cross-owner service allowed';exception when raise_exception then if sqlerrm='Cross-owner service allowed' then raise;end if;end;
 begin perform public.claim_email_jobs('fake-token');raise exception 'Secret API accessible';exception when insufficient_privilege then null;end;
end$$;
reset role;
update private.app_members set approved=false where user_id='be5e8020-4ae5-41db-ad68-ddddda160103';
set local role authenticated;
do $$begin begin perform private.api_pre_request();raise exception 'Revocation ignored';exception when sqlstate 'PT401' then null;end;end$$;
reset role;
update private.app_members set approved=true where user_id='be5e8020-4ae5-41db-ad68-ddddda160103';
delete from auth.sessions where id='be5e8020-4ae5-41db-ad68-ddddda161103';
set local role authenticated;
do $$begin begin perform private.api_pre_request();raise exception 'Logged-out session allowed';exception when sqlstate 'PT401' then null;end;end$$;
reset role;
rollback;
select 'Admin bootstrap, token/session checks, pending 401, self-approval denial, owner isolation, service transaction, usage and revocation: passed. All test data rolled back.' as result;
