begin;
create function private.photo_inventory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.check_access();
 return coalesce((select jsonb_object_agg(service_id,files) from (
  select split_part(name,'/',2) service_id,jsonb_agg(split_part(name,'/',3) order by name) files
  from storage.objects where bucket_id='liftcare-photos' and split_part(name,'/',1)=auth.uid()::text group by split_part(name,'/',2)
 ) inventory),'{}'::jsonb);
end $$;
revoke all on function private.photo_inventory() from public,anon;
grant execute on function private.photo_inventory() to authenticated;
create function public.photo_inventory() returns jsonb language sql security invoker set search_path='' as $$select private.photo_inventory();$$;
revoke all on function public.photo_inventory() from public,anon;
grant execute on function public.photo_inventory() to authenticated;
notify pgrst,'reload schema';
commit;
