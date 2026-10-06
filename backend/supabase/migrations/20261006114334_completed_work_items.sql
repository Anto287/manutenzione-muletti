begin;
create function private.record_completed_work(
  p_machine_id text, p_plan_ids text[], p_date date, p_reading numeric,
  p_cost numeric default 0, p_technician text default '', p_notes text default '',p_items jsonb default '[]'::jsonb
) returns public.service_records language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  m public.machines;
  result public.service_records;
  work jsonb;
  count_plans integer;
begin
  perform private.check_access();
  p_plan_ids:=coalesce(p_plan_ids,array[]::text[]);
  p_items:=coalesce(p_items,'[]'::jsonb);
  if jsonb_typeof(p_items)<>'array' then raise exception 'Lavori non validi';end if;
  if jsonb_array_length(p_items)>40 or exists(select 1 from jsonb_array_elements(p_items) i where jsonb_typeof(i)<>'object' or jsonb_typeof(i->'name') is distinct from 'string' or length(trim(i->>'name')) not between 1 and 100 or (i ? 'part' and jsonb_typeof(i->'part') is distinct from 'string') or length(coalesce(i->>'part',''))>120) then raise exception 'Lavori non validi';end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(distinct lower(trim(i->>'name'))) from jsonb_array_elements(p_items) i) then raise exception 'Lavori duplicati';end if;
  if p_cost is null or p_cost<0 or p_cost::text in ('NaN','Infinity','-Infinity') then raise exception 'Costo non valido';end if;
  select * into m from public.machines where owner_id=u and id=p_machine_id for update;
  if not found then raise exception 'Mezzo non disponibile'; end if;
  if p_date is null or p_date > (now() at time zone 'Europe/Rome')::date or
     p_reading is null or p_reading::text in ('NaN','Infinity','-Infinity') or p_reading < m.reading or
     (m.unit='km' and p_reading<>trunc(p_reading)) then
    raise exception 'Data o contatore non validi';
  end if;
  if cardinality(p_plan_ids)+jsonb_array_length(p_items)=0 then raise exception 'Seleziona almeno un lavoro'; end if;
  perform 1 from public.maintenance_plans where owner_id=u and machine_id=m.id and id=any(p_plan_ids) order by id for update;
  select count(*),jsonb_agg(jsonb_build_object('name',name,'part',part) order by id)
    into count_plans,work from public.maintenance_plans
    where owner_id=u and machine_id=m.id and id=any(p_plan_ids);
  if count_plans<>cardinality(p_plan_ids) then raise exception 'Piani non validi o duplicati'; end if;
  if exists(select 1 from public.maintenance_plans where owner_id=u and machine_id=m.id and id=any(p_plan_ids)
    and (last_date>p_date or last_reading>p_reading)) then raise exception 'Intervento precedente al piano'; end if;
  work:=coalesce(work,'[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object('name',trim(i->>'name'),'part',trim(coalesce(i->>'part','')))) from jsonb_array_elements(p_items) i),'[]'::jsonb);
  insert into public.service_records(owner_id,machine_id,machine_name,machine_type,unit,date,reading,cost,technician,notes,items)
    values(u,m.id,m.name,m.type,m.unit,p_date,p_reading,p_cost,p_technician,p_notes,work) returning * into result;
  update public.machines set reading=p_reading where owner_id=u and id=m.id;
  update public.maintenance_plans set last_date=p_date,last_reading=p_reading
    where owner_id=u and machine_id=m.id and id=any(p_plan_ids);
  return result;
end $$;
revoke all on function private.record_completed_work(text,text[],date,numeric,numeric,text,text,jsonb) from public,anon;
grant execute on function private.record_completed_work(text,text[],date,numeric,numeric,text,text,jsonb) to authenticated;
create function public.record_completed_work(p_machine_id text,p_plan_ids text[],p_date date,p_reading numeric,p_cost numeric default 0,p_technician text default '',p_notes text default '',p_items jsonb default '[]'::jsonb) returns public.service_records language sql security invoker set search_path='' as $$select private.record_completed_work(p_machine_id,p_plan_ids,p_date,p_reading,p_cost,p_technician,p_notes,p_items);$$;
revoke all on function public.record_completed_work(text,text[],date,numeric,numeric,text,text,jsonb) from public,anon;
grant execute on function public.record_completed_work(text,text[],date,numeric,numeric,text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
