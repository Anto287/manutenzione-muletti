import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.env.LIFTCARE_PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const owner='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key);
    insert into auth.users values('${owner}'),('${other}');
    create function auth.uid() returns uuid language sql stable as
      'select nullif(current_setting(''request.jwt.claim.sub'',true),'''')::uuid';
    grant usage on schema auth,storage,public to authenticated,anon;
    grant execute on function auth.uid() to authenticated,anon;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text, unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant select,insert,delete on storage.objects to authenticated;
  `);
  await db.exec(await readFile(new URL('./supabase/migrations/202610060001_liftcare.sql',import.meta.url),'utf8'));
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${owner}',false)`);
  await db.exec(`insert into public.machines(id,name,type,unit,reading) values('m1','TR-01','tractor','h',120);
    insert into public.maintenance_plans(id,machine_id,name,interval,last_reading,last_date)
    values('p1','m1','Filtro gasolio',250,120,'2020-01-01');`);
  await assert.rejects(db.exec(`update public.machines set reading=119 where id='m1'`),/contatore/);
  await assert.rejects(db.exec(`update public.machines set unit='km' where id='m1'`),/Unità/);
  await assert.rejects(db.exec(`select public.record_service('m1',array['p1','p1'],'2020-01-02',125)`),/duplicati/);
  await assert.rejects(db.exec(`select public.record_service('m1',array['p1'],'2999-01-01',125)`),/validi/);
  await assert.rejects(db.exec(`select public.record_service('m1',array['p1'],'2020-01-02',125,-1)`));
  assert.equal((await db.query(`select reading from public.machines`)).rows[0].reading,'120');
  const service=(await db.query(`select (public.record_service('m1',array['p1'],'2020-01-02',125)).*`)).rows[0];
  assert.equal(service.items[0].name,'Filtro gasolio');
  assert.equal((await db.query(`select last_reading from public.maintenance_plans`)).rows[0].last_reading,'125');
  await assert.rejects(db.exec(`delete from public.service_records`),/permission denied/);
  await assert.rejects(db.exec(`delete from public.machines where id='m1'`),/foreign key/);
  await db.exec(`insert into storage.objects(bucket_id,name) values('liftcare-photos','${owner}/${service.id}/1.jpg')`);
  await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name) values('liftcare-photos','${owner}/${service.id}/1.png')`),/row-level security/);
  await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name) values('liftcare-photos','${owner}/${service.id}/7.jpg')`),/row-level security/);
  await assert.rejects(db.exec(`insert into storage.objects(bucket_id,name) values('liftcare-photos','${owner}/missing/2.jpg')`),/row-level security/);
  await db.exec(`select set_config('request.jwt.claim.sub','${other}',false)`);
  assert.equal((await db.query(`select * from public.machines`)).rows.length,0);
  assert.equal((await db.query(`select * from public.service_records`)).rows.length,0);
  assert.equal((await db.query(`select * from storage.objects`)).rows.length,0);
  await assert.rejects(db.exec(`select public.record_service('m1',array['p1'],'2020-01-02',130)`),/disponibile/);
  await assert.rejects(db.exec(`insert into public.maintenance_plans(machine_id,name,months,last_date) values('m1','Aria',12,'2020-01-01')`),/disponibile/);
  await assert.rejects(db.exec(`insert into public.machines(owner_id,name,type,unit) values('${owner}','Intruso','car','km')`),/row-level security/);
  await db.exec(`set role anon; select set_config('request.jwt.claim.sub','',false)`);
  await assert.rejects(db.query(`select * from public.machines`),/permission denied/);
  await assert.rejects(db.query(`select public.record_service('m1',array['p1'],'2020-01-02',130)`),/permission denied/);
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${owner}',false); delete from public.maintenance_plans where id='p1'`);
  assert.equal((await db.query(`select items from public.service_records`)).rows[0].items[0].name,'Filtro gasolio');
  console.log('Database: migrazione, isolamento utenti, contatori, transazioni, storico e policy foto verificati.');
} finally { await db.close(); }
