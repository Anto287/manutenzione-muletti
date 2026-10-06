begin;
create function public.import_archive(archive jsonb) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); v jsonb; t jsonb; h jsonb;
begin
 if u is null then raise exception 'Accesso richiesto'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.machines where owner_id=u) then raise exception 'Importazione consentita soltanto in un archivio online vuoto'; end if;
 if archive->>'version'<>'2' or jsonb_typeof(archive->'vehicles')<>'array' or jsonb_typeof(archive->'tasks')<>'array' or jsonb_typeof(archive->'history')<>'array' then raise exception 'Backup non valido'; end if;
 for v in select * from jsonb_array_elements(archive->'vehicles') loop
  insert into public.machines(owner_id,id,name,type,model,serial,plate,power,unit,reading) values(u,v->>'id',v->>'name',v->>'type',v->>'model',v->>'serial',v->>'plate',v->>'power',v->>'unit',(v->>'reading')::numeric);
 end loop;
 for t in select * from jsonb_array_elements(archive->'tasks') loop
  insert into public.maintenance_plans(owner_id,id,machine_id,name,part,interval,months,last_reading,last_date) values(u,t->>'id',t->>'vehicleId',t->>'name',t->>'part',(t->>'interval')::numeric,(t->>'months')::integer,(t->>'lastReading')::numeric,(t->>'lastDate')::date);
 end loop;
 for h in select * from jsonb_array_elements(archive->'history') loop
  if (h->>'date')::date>(now() at time zone 'Europe/Rome')::date or not exists(select 1 from public.machines where owner_id=u and id=h->>'vehicleId' and unit=h->>'unit' and type=h->>'vehicleType' and reading>=(h->>'reading')::numeric) or jsonb_typeof(h->'items')<>'array' or jsonb_array_length(h->'items')=0 then raise exception 'Storico non valido'; end if;
  insert into public.service_records(owner_id,id,machine_id,machine_name,machine_type,unit,date,reading,cost,technician,notes,items) values(u,h->>'id',h->>'vehicleId',h->>'vehicleName',h->>'vehicleType',h->>'unit',(h->>'date')::date,(h->>'reading')::numeric,(h->>'cost')::numeric,h->>'technician',h->>'notes',h->'items');
 end loop;
end $$;
revoke all on function public.import_archive(jsonb) from public,anon;
grant execute on function public.import_archive(jsonb) to authenticated;
commit;
