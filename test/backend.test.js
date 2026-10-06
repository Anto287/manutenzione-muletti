import {test} from 'node:test';
import assert from 'node:assert/strict';
import {LiftCareBackend} from '../src/backend.js';
const setup=(responses=[])=>{
  const calls=[];
  const api=new LiftCareBackend({url:'https://example.supabase.co',publishableKey:'public',fetch:async(url,options)=>{
    calls.push({url,options});
    const next=responses.shift() || {status:200,data:[]};
    return new Response(JSON.stringify(next.data),{status:next.status});
  }});
  return {api,calls};
};
test('backend requires authentication before reading or changing records',async()=>{
  const {api,calls}=setup();
  await assert.rejects(api.list('machines'),/Accedi/);
  assert.equal(calls.length,0);
});
test('sign in sets session and sends bearer token only after authentication',async()=>{
  const {api,calls}=setup([{status:200,data:{access_token:'token',user:{id:'u1'}}},{status:200,data:[]}]);
  await api.signIn('test@example.com','password');
  await api.list('machines',{offset:100,limit:100});
  assert.equal(calls[0].options.headers.Authorization,undefined);
  assert.equal(calls[1].options.headers.Authorization,'Bearer token');
  assert.match(calls[1].url,/offset=100&limit=100/);
});
test('immutable resources and owner fields cannot be submitted',async()=>{
  const {api,calls}=setup();
  await assert.rejects(api.saveMachine({owner_id:'other'}),/sistema/);
  await assert.rejects(api.write('service_records',{notes:'rewrite'}),/modificabile/);
  assert.equal(calls.length,0);
});
test('service registration uses one transactional RPC with plan ids',async()=>{
  const {api,calls}=setup(); api.session={access_token:'token'};
  await api.recordService({machineId:'m1',planIds:['p1'],date:'2026-10-06',reading:125});
  assert.match(calls[0].url,/rpc\/record_service$/);
  assert.deepEqual(JSON.parse(calls[0].options.body).p_plan_ids,['p1']);
});
test('photo rejects oversize or bad slots and uploads binary without overwrite',async()=>{
  const {api,calls}=setup();api.session={access_token:'token',user:{id:'u1'}};
  await assert.rejects(api.uploadPhoto('s1',1,new Blob([new Uint8Array(160001)],{type:'image/jpeg'})),/160 KB/);
  await assert.rejects(api.uploadPhoto('s1',7,new Blob(['jpeg'],{type:'image/jpeg'})),/valido/);
  const blob=new Blob(['jpeg'],{type:'image/jpeg'});
  assert.equal(await api.uploadPhoto('s1',1,blob),'u1/s1/1.jpg');
  assert.equal(calls[0].options.body,blob);
  assert.equal(calls[0].options.headers['x-upsert'],'false');
});
test('errors are surfaced and logout clears the local session even on failure',async()=>{
  const {api}=setup([{status:401,data:{message:'Expired'}}]);api.session={access_token:'token'};
  await assert.rejects(api.signOut(),/Expired/);
  assert.equal(api.session,null);
});
