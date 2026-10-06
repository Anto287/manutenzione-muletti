begin;
create table private.admin_emails(email text primary key);
create table private.app_members(user_id uuid primary key references auth.users(id) on delete cascade,email text not null,approved boolean not null default false,is_admin boolean not null default false,requested_at timestamptz not null default now(),approved_at timestamptz);
alter table private.admin_emails enable row level security;
alter table private.app_members enable row level security;
revoke all on private.admin_emails,private.app_members from public,anon,authenticated;
create table private.access_email_outbox(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,email text not null,created_at timestamptz not null default now(),sent_at timestamptz,unique(user_id));
alter table private.access_email_outbox enable row level security;
revoke all on private.access_email_outbox from public,anon,authenticated;
create function private.sync_member() returns trigger language plpgsql security definer set search_path='' as $$
declare admin boolean;
begin
 if new.email_confirmed_at is null then return new; end if;
 select exists(select 1 from private.admin_emails where email=lower(new.email)) into admin;
 insert into private.app_members(user_id,email,approved,is_admin,approved_at) values(new.id,new.email,admin,admin,case when admin then now() end)
 on conflict(user_id) do update set email=excluded.email,approved=case when private.app_members.is_admin and not admin then false when admin then true else private.app_members.approved end,is_admin=admin;
 if not admin then insert into private.access_email_outbox(user_id,email) values(new.id,new.email) on conflict(user_id) do nothing; end if;
 return new;
end $$;
revoke all on function private.sync_member() from public,anon,authenticated;
create trigger liftcare_member after insert or update of email,email_confirmed_at on auth.users for each row execute function private.sync_member();
create function private.is_approved() returns boolean language sql stable security definer set search_path='' as $$ select coalesce((select approved from private.app_members where user_id=auth.uid()),false); $$;
create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select coalesce((select approved and is_admin from private.app_members where user_id=auth.uid()),false); $$;
revoke all on function private.is_approved(),private.is_admin() from public,anon;
grant execute on function private.is_approved(),private.is_admin() to authenticated;
create function private.check_access() returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise sqlstate 'PT401' using message='Accesso richiesto'; end if;
 if not private.is_approved() then raise sqlstate 'PT403' using message='Account in attesa di approvazione dell’admin'; end if;
end $$;
revoke all on function private.check_access() from public,anon;
grant execute on function private.check_access() to authenticated;
create function private.api_pre_request() returns void language plpgsql set search_path='' as $$
begin
 if current_user='service_role' then return; end if;
 if coalesce(current_setting('request.path',true),'') in ('/rpc/access_status') then return; end if;
 if auth.uid() is null then raise sqlstate 'PT401' using message='Accesso richiesto'; end if;
 perform private.check_access();
end $$;
grant usage on schema private to anon;
revoke all on function private.api_pre_request() from public;
grant execute on function private.api_pre_request() to anon,authenticated,service_role;
alter role authenticator set pgrst.db_pre_request='private.api_pre_request';
create function private.access_status() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('approved',approved,'is_admin',is_admin) from private.app_members where user_id=auth.uid()),'{"approved":false,"is_admin":false}'::jsonb);
$$;
create function private.list_access_requests() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',user_id,'email',email,'approved',approved,'is_admin',is_admin,'requested_at',requested_at) order by requested_at desc) from private.app_members),'[]'::jsonb);
end $$;
create function private.set_user_approval(target_user uuid,allow_access boolean) returns void language plpgsql security definer set search_path='' as $$ begin
 if not private.is_admin() then raise sqlstate 'PT403' using message='Solo admin'; end if;
 if exists(select 1 from private.app_members where user_id=target_user and is_admin) then raise exception 'Il ruolo admin non si modifica da questa funzione'; end if;
 update private.app_members set approved=allow_access,approved_at=case when allow_access then now() else null end where user_id=target_user;
 if not found then raise exception 'Utente non disponibile'; end if;
end $$;
revoke all on function private.access_status(),private.list_access_requests(),private.set_user_approval(uuid,boolean) from public,anon;
grant execute on function private.access_status(),private.list_access_requests(),private.set_user_approval(uuid,boolean) to authenticated;
create function public.access_status() returns jsonb language sql security invoker set search_path='' as $$select private.access_status();$$;
create function public.list_access_requests() returns jsonb language sql security invoker set search_path='' as $$select private.list_access_requests();$$;
create function public.set_user_approval(target_user uuid,allow_access boolean) returns void language sql security invoker set search_path='' as $$select private.set_user_approval(target_user,allow_access);$$;
revoke all on function public.access_status(),public.list_access_requests(),public.set_user_approval(uuid,boolean) from public,anon;
grant execute on function public.access_status(),public.list_access_requests(),public.set_user_approval(uuid,boolean) to authenticated;
-- Restrictive policies combine with ownership policies using AND.
create policy machines_approved on public.machines as restrictive to authenticated using((select private.is_approved())) with check((select private.is_approved()));
create policy plans_approved on public.maintenance_plans as restrictive to authenticated using((select private.is_approved())) with check((select private.is_approved()));
create policy records_approved on public.service_records as restrictive to authenticated using((select private.is_approved()));
create policy photos_approved on storage.objects as restrictive to authenticated using(bucket_id<>'liftcare-photos' or (select private.is_approved())) with check(bucket_id<>'liftcare-photos' or (select private.is_approved()));
create or replace function public.record_service(p_machine_id text,p_plan_ids text[],p_date date,p_reading numeric,p_cost numeric default 0,p_technician text default '',p_notes text default '') returns public.service_records language plpgsql security invoker set search_path='' as $$begin perform private.check_access();return private.record_service(p_machine_id,p_plan_ids,p_date,p_reading,p_cost,p_technician,p_notes);end$$;
create or replace function public.import_archive(archive jsonb) returns void language plpgsql security invoker set search_path='' as $$begin perform private.check_access();perform private.import_archive(archive);end$$;
notify pgrst,'reload config';
notify pgrst,'reload schema';
commit;
