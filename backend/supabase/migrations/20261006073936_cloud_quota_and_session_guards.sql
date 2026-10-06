begin;
-- Authorization is read from the database for every request, not user-editable JWT metadata.
create function private.session_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s where s.user_id=auth.uid() and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after>now()));
$$;
revoke all on function private.session_active() from public,anon;
grant execute on function private.session_active() to authenticated;
create or replace function private.is_approved() returns boolean language sql stable security definer set search_path='' as $$
 select private.session_active() and coalesce((select approved from private.app_members where user_id=auth.uid()),false);
$$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select private.session_active() and coalesce((select approved and is_admin from private.app_members where user_id=auth.uid()),false);
$$;
create or replace function private.check_access() returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not private.session_active() then raise sqlstate 'PT401' using message='Sessione non valida: accedi nuovamente'; end if;
 if not private.is_approved() then raise sqlstate 'PT401' using message='Account in attesa di approvazione dell’admin'; end if;
end $$;
create or replace function private.access_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.session_active() then raise sqlstate 'PT401' using message='Sessione non valida'; end if;
 return coalesce((select jsonb_build_object('approved',approved,'is_admin',is_admin) from private.app_members where user_id=auth.uid()),'{"approved":false,"is_admin":false}'::jsonb);
end $$;
create function private.photo_usage() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare total_bytes bigint; own_bytes bigint; count_photos bigint;
begin
 perform private.check_access();
 select coalesce(sum(coalesce((metadata->>'size')::bigint,160000)),0),coalesce(sum(coalesce((metadata->>'size')::bigint,160000)) filter(where bucket_id='liftcare-photos' and split_part(name,'/',1)=auth.uid()::text),0),count(*) filter(where bucket_id='liftcare-photos' and split_part(name,'/',1)=auth.uid()::text)
 into total_bytes,own_bytes,count_photos from storage.objects;
 return jsonb_build_object('used_bytes',total_bytes,'own_bytes',own_bytes,'photo_count',count_photos,'limit_bytes',1000000000,'warning',total_bytes>=800000000,'blocked',total_bytes+160000>1000000000);
end $$;
revoke all on function private.photo_usage() from public,anon;
grant execute on function private.photo_usage() to authenticated;
create function public.photo_usage() returns jsonb language sql security invoker set search_path='' as $$select private.photo_usage();$$;
revoke all on function public.photo_usage() from public,anon;
grant execute on function public.photo_usage() to authenticated;
-- Serialize inserts and account for pending objects at their maximum file size.
create or replace function private.can_upload_photo(object_name text) returns boolean language plpgsql volatile security definer set search_path='' as $$
begin
 if not private.is_approved() or split_part(object_name,'/',1)<>auth.uid()::text or object_name !~ '^[^/]+/[^/]+/[1-6]\.(jpg|png|webp)$' then return false; end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-photo-quota',0));
 return exists(select 1 from public.service_records where owner_id=auth.uid() and id=split_part(object_name,'/',2))
 and not exists(select 1 from storage.objects where bucket_id='liftcare-photos' and split_part(name,'/',1)=auth.uid()::text and split_part(name,'/',2)=split_part(object_name,'/',2) and split_part(split_part(name,'/',3),'.',1)=split_part(split_part(object_name,'/',3),'.',1))
 and (select coalesce(sum(coalesce((metadata->>'size')::bigint,160000)),0)+160000<=1000000000 from storage.objects);
end $$;
revoke all on function public.guard_machine(),public.guard_plan() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
