begin;
-- The sending key never leaves server-side service-role calls.
create table private.registration_email_limits(email text primary key,day date not null,attempts integer not null,last_attempt timestamptz not null);
alter table private.registration_email_limits enable row level security;
revoke all on private.registration_email_limits from public,anon,authenticated;
create function private.claim_registration_email(recipient text) returns jsonb language plpgsql security definer set search_path='' as $$
declare config private.email_config; state private.registration_email_limits; email_value text:=lower(trim(recipient)); key_value text;
begin
 if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','')<>'service_role' then raise sqlstate 'PT401' using message='Accesso richiesto';end if;
 -- Test sender can send only to the configured account owner. No arbitrary recipients.
 if not exists(select 1 from private.admin_emails where email=email_value) then return '{"eligible":false}'::jsonb;end if;
 select * into config from private.email_config;
 if not found then raise sqlstate 'PT503' using message='Email non configurate';end if;
 perform pg_advisory_xact_lock(hashtextextended('liftcare-registration:'||email_value,0));
 select * into state from private.registration_email_limits where email=email_value;
 if found and (state.last_attempt>now()-interval '60 seconds' or (state.day=current_date and state.attempts>=5)) then raise sqlstate 'PT429' using message='Limite invii';end if;
 insert into private.registration_email_limits(email,day,attempts,last_attempt) values(email_value,current_date,1,now()) on conflict(email) do update set day=current_date,attempts=case when private.registration_email_limits.day=current_date then private.registration_email_limits.attempts+1 else 1 end,last_attempt=now();
 select decrypted_secret into key_value from vault.decrypted_secrets where id=config.key_id;
 return jsonb_build_object('eligible',true,'key',key_value,'sender',config.from_email,'attempt_id',gen_random_uuid());
end$$;
revoke all on function private.claim_registration_email(text) from public,anon,authenticated;
grant execute on function private.claim_registration_email(text) to service_role;
create function public.claim_registration_email(recipient text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_registration_email(recipient);$$;
revoke all on function public.claim_registration_email(text) from public,anon,authenticated;
grant execute on function public.claim_registration_email(text) to service_role;
notify pgrst,'reload schema';
commit;
