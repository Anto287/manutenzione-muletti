// Public signup initiation; access is granted only after Supabase verifies the email token.
// Only the configured admin recipient is supported without a verified sender domain.
const site='https://anto287.github.io/manutenzione-muletti/';
Deno.serve(async (req: Request) => {
 const origin=req.headers.get('Origin');
 const headers={'Access-Control-Allow-Origin':'https://anto287.github.io','Access-Control-Allow-Headers':'apikey,authorization,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(body:unknown,status=200)=>Response.json(body,{status,headers});
 if(origin&&origin!=='https://anto287.github.io')return reply({message:'Origine non consentita.'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({message:'Metodo non consentito.'},405);
 if(Number(req.headers.get('Content-Length')||0)>2048)return reply({message:'Richiesta troppo grande.'},413);
 let input;
 try{const raw=await req.text();if(raw.length>2048)return reply({message:'Richiesta troppo grande.'},413);input=JSON.parse(raw)}catch{return reply({message:'Dati non validi.'},400)}
 const email=typeof input.email==='string'?input.email.trim().toLowerCase():'';
 const password=input.password;
 if(email.length>254||!email.includes('@')||typeof password!=='string'||password.length<8||password.length>128)return reply({message:'Inserisci email e password di almeno 8 caratteri.'},400);
 const base=Deno.env.get('SUPABASE_URL')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const authHeaders={apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};
 let config;
 try{
  const r=await fetch(`${base}/rest/v1/rpc/claim_registration_email`,{method:'POST',headers:authHeaders,body:JSON.stringify({recipient:email}),signal:AbortSignal.timeout(10000)});
  if(!r.ok)return reply({message:'Attendi un minuto e riprova. Sono consentiti al massimo 5 invii al giorno.'},r.status===429?429:503);
  config=await r.json();
 }catch{return reply({message:'Servizio momentaneamente non disponibile.'},503)}
 if(!config.eligible)return reply({supported:false});
 // The admin password is stored by Supabase Auth, never by this function or in application tables.
 try{
  const generated=await fetch(`${base}/auth/v1/admin/generate_link`,{method:'POST',headers:authHeaders,body:JSON.stringify({type:'signup',email,password}),signal:AbortSignal.timeout(10000)});
  if(!generated.ok)return reply({message:'Registrazione non riuscita. Se hai già confermato l’account, premi Accedi.'},400);
  const link=await generated.json();
  const hash=link.hashed_token||link.properties?.hashed_token;
  if(typeof hash!=='string'||!/^[a-zA-Z0-9_-]{20,200}$/.test(hash))throw Error('Invalid confirmation');
  const confirmation=`${site}#token_hash=${encodeURIComponent(hash)}&type=signup`;
  const sent=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${config.key}`,'Content-Type':'application/json','Idempotency-Key':`liftcare-confirm-${config.attempt_id}`},body:JSON.stringify({from:config.sender,to:[email],subject:'Conferma il tuo account LiftCare',text:`Benvenuto in LiftCare.\n\nPer confermare il tuo indirizzo e aprire il gestionale, usa questo link:\n${confirmation}\n\nIl link è personale, monouso e scade secondo le impostazioni di Supabase Auth. Se non hai richiesto la registrazione, ignora questa email.`}),signal:AbortSignal.timeout(10000)});
  if(!sent.ok)return reply({message:'Email non inviata. Attendi un minuto e riprova Crea account.'},502);
  return reply({supported:true,sent:true});
 }catch{return reply({message:'Invio non riuscito. Attendi un minuto e riprova.'},503)}
});
