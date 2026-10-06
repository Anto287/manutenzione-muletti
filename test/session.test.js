import test from 'node:test';
import assert from 'node:assert/strict';
import {createSessionManager,SESSION_KEY} from '../src/session.js';
const storage=()=>{const m=new Map();return {getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,v),removeItem:k=>m.delete(k)}};
const session=(expired=false)=>({access_token:'access',refresh_token:'refresh',expires_at:expired?1:Date.now()/1000+3600,user:{id:'owner',email:'owner@example.test'},password:'must-not-be-stored'});
test('closing and reopening restores persistent login without storing passwords or unnecessary refresh',async()=>{
 const persistent=storage(),legacy=storage(),api={session:session(),refreshSession:()=>{throw Error('Unnecessary refresh')}};
 createSessionManager({api,storage:persistent,legacyStorage:legacy}).save();assert.ok(!persistent.getItem(SESSION_KEY).includes('must-not-be-stored'));
 api.session=null;await createSessionManager({api,storage:persistent,legacyStorage:storage()}).restore();assert.equal(api.session.user.id,'owner');
});
test('existing tab sessions migrate to persistent storage and clear legacy tokens',async()=>{
 const persistent=storage(),legacy=storage();legacy.setItem(SESSION_KEY,JSON.stringify(session()));const api={session:null};await createSessionManager({api,storage:persistent,legacyStorage:legacy}).restore();assert.equal(api.session.user.id,'owner');assert.ok(persistent.getItem(SESSION_KEY));assert.equal(legacy.getItem(SESSION_KEY),null);
});
test('concurrent refreshes share one request and persist the rotated refresh token',async()=>{
 const persistent=storage();let calls=0;const api={session:session(true),async refreshSession(){calls++;await Promise.resolve();this.session={...session(),refresh_token:'rotated'}}};const manager=createSessionManager({api,storage:persistent});manager.save();await Promise.all([manager.ensure(),manager.ensure(),manager.ensure()]);assert.equal(calls,1);assert.equal(JSON.parse(persistent.getItem(SESSION_KEY)).refresh_token,'rotated');
});
test('temporary network failure preserves login while an invalid refresh token clears it',async()=>{
 for(const status of [undefined,503,400,401]){const persistent=storage(),api={session:session(true),async refreshSession(){throw Object.assign(Error('failure'),{status})}};const manager=createSessionManager({api,storage:persistent});manager.save();await assert.rejects(manager.ensure());assert.equal(!!persistent.getItem(SESSION_KEY),![400,401].includes(status));assert.equal(!!api.session,![400,401].includes(status))}
});
test('logout during a refresh cannot resurrect the saved login',async()=>{
 const persistent=storage();let finish;const api={session:session(true),async refreshSession(){await new Promise(resolve=>finish=resolve);this.session=session()}};const manager=createSessionManager({api,storage:persistent});manager.save();const pending=manager.ensure();manager.clear();finish();await assert.rejects(pending);assert.equal(api.session,null);assert.equal(persistent.getItem(SESSION_KEY),null);
});
test('two tabs serialize refresh token rotation and reuse the latest session',async()=>{
 const persistent=storage();let queued=Promise.resolve(),calls=0;const locks={request(name,task){const next=queued.then(task);queued=next.catch(()=>{});return next}};
 const make=()=>({session:session(true),async refreshSession(){calls++;await Promise.resolve();this.session={...session(),refresh_token:'new-refresh'}}});
 const a=make(),b=make(),ma=createSessionManager({api:a,storage:persistent,locks}),mb=createSessionManager({api:b,storage:persistent,locks});ma.save();await Promise.all([ma.restore(),mb.restore()]);assert.equal(calls,1);assert.equal(b.session.refresh_token,'new-refresh');
});
