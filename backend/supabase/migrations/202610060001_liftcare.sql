begin;

create table public.machines (
  id text not null default gen_random_uuid()::text,
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null check (length(trim(name)) between 1 and 80),
  type text not null check (type in ('forklift','car','tractor')),
  model text not null default '' check (length(model) <= 100),
  serial text not null default '' check (length(serial) <= 100),
  plate text not null default '' check (length(plate) <= 20),
  power text not null default '',
  unit text not null check (unit in ('h','km')),
  reading numeric not null default 0 check (reading >= 0 and reading <> 'NaN'::numeric),
  created_at timestamptz not null default now(),
  primary key (owner_id, id),
  check (unit <> 'km' or reading = trunc(reading))
);
create unique index machines_owner_name on public.machines(owner_id, lower(trim(name)));

create table public.maintenance_plans (
  id text not null default gen_random_uuid()::text,
  owner_id uuid not null default auth.uid(),
  machine_id text not null,
  name text not null check (length(trim(name)) between 1 and 100),
  part text not null default '' check (length(part) <= 200),
  interval numeric not null default 0 check (interval >= 0 and interval <> 'NaN'::numeric),
  months integer not null default 0 check (months >= 0),
  last_reading numeric not null default 0 check (last_reading >= 0 and last_reading <> 'NaN'::numeric),
  last_date date not null,
  primary key (owner_id,id),
  foreign key (owner_id,machine_id) references public.machines(owner_id,id),
  check (interval > 0 or months > 0)
);
create index maintenance_plans_machine on public.maintenance_plans(owner_id,machine_id);

create table public.service_records (
  id text not null default gen_random_uuid()::text,
  owner_id uuid not null default auth.uid(),
  machine_id text not null,
  machine_name text not null,
  machine_type text not null,
  unit text not null,
  date date not null,
  reading numeric not null check (reading >= 0 and reading <> 'NaN'::numeric),
  cost numeric not null default 0 check (cost >= 0 and cost <> 'NaN'::numeric),
  technician text not null default '' check (length(technician) <= 120),
  notes text not null default '' check (length(notes) <= 2000),
  items jsonb not null check (jsonb_typeof(items) = 'array'),
  primary key (owner_id,id),
  foreign key (owner_id,machine_id) references public.machines(owner_id,id)
);
create index service_records_machine on public.service_records(owner_id,machine_id,date desc);

alter table public.machines enable row level security;
alter table public.maintenance_plans enable row level security;
alter table public.service_records enable row level security;
revoke all on public.machines, public.maintenance_plans, public.service_records from anon, authenticated;
grant select,insert,update,delete on public.machines, public.maintenance_plans to authenticated;
grant select on public.service_records to authenticated;
create policy machines_owner on public.machines to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy plans_owner on public.maintenance_plans to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy records_owner on public.service_records for select to authenticated
  using (owner_id = (select auth.uid()));

create function public.guard_machine() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.owner_id <> old.owner_id or new.id <> old.id then
    raise exception 'Identificativo e proprietario non modificabili';
  end if;
  if new.unit = old.unit and new.reading < old.reading then
    raise exception 'Il contatore non può diminuire';
  end if;
  if new.unit <> old.unit and (
    exists (select 1 from public.maintenance_plans where owner_id=old.owner_id and machine_id=old.id) or
    exists (select 1 from public.service_records where owner_id=old.owner_id and machine_id=old.id)
  ) then raise exception 'Unità bloccata: il mezzo ha piani o storico'; end if;
  return new;
end $$;
create trigger guard_machine before update on public.machines for each row execute function public.guard_machine();

create function public.guard_plan() returns trigger language plpgsql set search_path = '' as $$
declare m public.machines;
begin
  if TG_OP='UPDATE' and (new.owner_id<>old.owner_id or new.id<>old.id or new.machine_id<>old.machine_id) then
    raise exception 'Identificativi del piano non modificabili';
  end if;
  select * into m from public.machines where owner_id=new.owner_id and id=new.machine_id for update;
  if not found then raise exception 'Mezzo non disponibile'; end if;
  if new.last_reading > m.reading or new.last_date > (now() at time zone 'Europe/Rome')::date then
    raise exception 'Contatore o data del piano non validi';
  end if;
  if m.unit='km' and (new.interval<>trunc(new.interval) or new.last_reading<>trunc(new.last_reading)) then
    raise exception 'Inserisci chilometri interi';
  end if;
  return new;
end $$;
create trigger guard_plan before insert or update on public.maintenance_plans for each row execute function public.guard_plan();

-- One transaction: lock the machine, snapshot work, update counter and plans.
-- Definer is needed because clients cannot write the immutable history directly.
create function public.record_service(
  p_machine_id text, p_plan_ids text[], p_date date, p_reading numeric,
  p_cost numeric default 0, p_technician text default '', p_notes text default ''
) returns public.service_records language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  m public.machines;
  result public.service_records;
  work jsonb;
  count_plans integer;
begin
  if u is null then raise exception 'Accesso richiesto'; end if;
  select * into m from public.machines where owner_id=u and id=p_machine_id for update;
  if not found then raise exception 'Mezzo non disponibile'; end if;
  if p_date is null or p_date > (now() at time zone 'Europe/Rome')::date or
     p_reading is null or p_reading='NaN'::numeric or p_reading < m.reading or
     (m.unit='km' and p_reading<>trunc(p_reading)) then
    raise exception 'Data o contatore non validi';
  end if;
  if coalesce(cardinality(p_plan_ids),0)=0 then raise exception 'Seleziona almeno un piano'; end if;
  perform 1 from public.maintenance_plans where owner_id=u and machine_id=m.id and id=any(p_plan_ids) order by id for update;
  select count(*),jsonb_agg(jsonb_build_object('name',name,'part',part) order by id)
    into count_plans,work from public.maintenance_plans
    where owner_id=u and machine_id=m.id and id=any(p_plan_ids);
  if count_plans<>cardinality(p_plan_ids) then raise exception 'Piani non validi o duplicati'; end if;
  if exists(select 1 from public.maintenance_plans where owner_id=u and machine_id=m.id and id=any(p_plan_ids)
    and (last_date>p_date or last_reading>p_reading)) then raise exception 'Intervento precedente al piano'; end if;
  insert into public.service_records(owner_id,machine_id,machine_name,machine_type,unit,date,reading,cost,technician,notes,items)
    values(u,m.id,m.name,m.type,m.unit,p_date,p_reading,p_cost,p_technician,p_notes,work) returning * into result;
  update public.machines set reading=p_reading where owner_id=u and id=m.id;
  update public.maintenance_plans set last_date=p_date,last_reading=p_reading
    where owner_id=u and machine_id=m.id and id=any(p_plan_ids);
  return result;
end $$;
revoke all on function public.record_service(text,text[],date,numeric,numeric,text,text) from public,anon;
grant execute on function public.record_service(text,text[],date,numeric,numeric,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('liftcare-photos','liftcare-photos',false,160000,array['image/jpeg','image/png','image/webp']);

-- Paths: user UUID / service ID / slot 1..6 . extension. No overwrite.
create function public.can_upload_photo(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and
    split_part(object_name,'/',1)=auth.uid()::text and
    object_name ~ '^[^/]+/[^/]+/[1-6]\.(jpg|png|webp)$' and
    exists(select 1 from public.service_records where owner_id=auth.uid() and id=split_part(object_name,'/',2)) and
    not exists(select 1 from storage.objects where bucket_id='liftcare-photos'
      and split_part(name,'/',1)=auth.uid()::text
      and split_part(name,'/',2)=split_part(object_name,'/',2)
      and split_part(split_part(name,'/',3),'.',1)=split_part(split_part(object_name,'/',3),'.',1));
$$;
revoke all on function public.can_upload_photo(text) from public,anon;
grant execute on function public.can_upload_photo(text) to authenticated;
create policy liftcare_photo_read on storage.objects for select to authenticated
  using(bucket_id='liftcare-photos' and split_part(name,'/',1)=(select auth.uid())::text);
create policy liftcare_photo_insert on storage.objects for insert to authenticated
  with check(bucket_id='liftcare-photos' and public.can_upload_photo(name));
create policy liftcare_photo_delete on storage.objects for delete to authenticated
  using(bucket_id='liftcare-photos' and split_part(name,'/',1)=(select auth.uid())::text);
commit;
