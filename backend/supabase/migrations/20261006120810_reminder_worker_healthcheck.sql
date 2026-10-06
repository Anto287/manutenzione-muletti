begin;
-- Authenticate diagnostic checks without leasing or cancelling any pending email job.
create function public.check_deadline_worker(job_token text) returns void language sql security invoker set search_path='' as $$select private.check_reminder_worker(job_token);$$;
revoke all on function public.check_deadline_worker(text) from public,anon,authenticated;
grant execute on function public.check_deadline_worker(text),private.check_reminder_worker(text) to service_role;
-- The old importer exists only as an implementation detail of the guarded wrapper.
revoke all on function private.import_archive_base(jsonb) from authenticated;
notify pgrst,'reload schema';
commit;
