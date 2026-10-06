begin;
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
alter function public.can_upload_photo(text) set schema private;
alter function public.record_service(text,text[],date,numeric,numeric,text,text) set schema private;
alter function public.import_archive(jsonb) set schema private;
create function public.record_service(p_machine_id text,p_plan_ids text[],p_date date,p_reading numeric,p_cost numeric default 0,p_technician text default '',p_notes text default '') returns public.service_records language sql security invoker set search_path='' as $$
 select private.record_service(p_machine_id,p_plan_ids,p_date,p_reading,p_cost,p_technician,p_notes);
$$;
create function public.import_archive(archive jsonb) returns void language sql security invoker set search_path='' as $$select private.import_archive(archive);$$;
revoke all on function public.record_service(text,text[],date,numeric,numeric,text,text),public.import_archive(jsonb) from public,anon;
grant execute on function public.record_service(text,text[],date,numeric,numeric,text,text),public.import_archive(jsonb) to authenticated;
commit;
