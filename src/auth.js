// Verification remains in Supabase Auth: no browser-supplied claim grants access.
export async function sendRegistration(api,email,password){
 const result=await api.request('/functions/v1/registration-email',{method:'POST',body:{email,password},authenticated:false});
 if(result?.supported===false){await api.request('/auth/v1/signup',{method:'POST',body:{email,password},authenticated:false});return;}
 if(!result?.sent)throw Error('Email non inviata. Riprova tra un minuto.');
}
export async function confirmRegistration(api,location,history){
 const params=new URLSearchParams(location.hash.slice(1));
 if(!params.has('token_hash'))return false;
 const token=params.get('token_hash');
 // Erase the one-time credential before any further navigation or network call.
 history.replaceState(null,'',location.pathname+location.search);
 if(params.get('type')!=='signup'||!token||!/^[a-zA-Z0-9_-]{20,200}$/.test(token))throw Error('Link di conferma non valido. Richiedi una nuova email.');
 const session=await api.request('/auth/v1/verify',{method:'POST',body:{token_hash:token,type:'signup'},authenticated:false});
 if(!session?.access_token||!session?.refresh_token||!session?.user)throw Error('Conferma non riuscita. Richiedi una nuova email.');
 api.session={...session,expires_at:Math.floor(Date.now()/1000)+session.expires_in};
 return true;
}
