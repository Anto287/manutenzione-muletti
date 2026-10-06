export const SESSION_KEY='liftcare-session-v1';
const valid=s=>s&&typeof s.access_token==='string'&&typeof s.refresh_token==='string'&&typeof s.user?.id==='string'&&typeof s.user?.email==='string';
export function createSessionManager({api,storage,legacyStorage,locks,now=Date.now}){
 let refreshing,managed=false;
 const read=source=>{try{const s=JSON.parse(source?.getItem(SESSION_KEY)||'null');return valid(s)?s:null}catch{return null}};
 const clear=()=>{managed=true;storage?.removeItem(SESSION_KEY);legacyStorage?.removeItem(SESSION_KEY)};
 const save=()=>{managed=true;if(!api.session){clear();return}const s=api.session;storage?.setItem(SESSION_KEY,JSON.stringify({access_token:s.access_token,refresh_token:s.refresh_token,expires_at:s.expires_at,user:{id:s.user.id,email:s.user.email}}));legacyStorage?.removeItem(SESSION_KEY)};
 const missing=()=>Error('Accedi per usare il tuo archivio online.');
 async function refresh(){
  // Re-read under the browser lock: another tab may already have rotated the tokens.
  if(managed&&storage){api.session=read(storage);if(!api.session)throw missing()}
  if(!api.session)throw missing();
  if(api.session.expires_at*1000>now()+60000)return;
  const prior=api.session,storedBefore=storage?.getItem(SESSION_KEY);
  try{
   await api.refreshSession();
   if(managed&&storage&&storage.getItem(SESSION_KEY)!==storedBefore){api.session=read(storage);if(!api.session)throw missing();return}
   save();
  }catch(error){
   // A connection failure must not erase a valid refresh token and force a new login.
   api.session=prior;
   if(managed&&storage&&storage.getItem(SESSION_KEY)!==storedBefore)api.session=read(storage);
   else if([400,401,403].includes(error.status)){api.session=null;clear()}
   throw error;
  }
 }
 async function ensure(){
  if(!api.session)throw missing();
  refreshing??=(locks?.request?locks.request('liftcare-session-refresh',refresh):refresh()).finally(()=>{refreshing=null});
  await refreshing;
 }
 async function restore(){
  api.session=read(storage)||read(legacyStorage);managed=true;
  if(!api.session){clear();return}
  if(!read(storage))save(); // Move an existing tab session without asking the user to sign in again.
  else legacyStorage?.removeItem(SESSION_KEY);
  try{await ensure()}catch(error){if([400,401,403].includes(error.status))return;/* Keep the session during a temporary outage; data calls report the connection error. */}
 }
 return {save,clear,restore,ensure};
}
