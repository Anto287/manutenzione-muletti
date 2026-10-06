// The only public request credential accepted is a private, server-generated job token.
// No CORS route or browser access; the provider API key is read from encrypted Vault.
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', {status:405});
  const token = req.headers.get('x-liftcare-job');
  if (!token || token.length > 200) return new Response('Unauthorized', {status:401});
  const base = Deno.env.get('SUPABASE_URL')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  async function rpc(name: string, body: unknown) {
    const r = await fetch(`${base}/rest/v1/rpc/${name}`, {method:'POST',signal:AbortSignal.timeout(10000),headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
    if (!r.ok) throw new Error(`rpc_${r.status}`);
    const text=await r.text();return text?JSON.parse(text):null;
  }
  let batch;
  try { batch=await rpc('claim_email_jobs',{job_token:token}); }
  catch { return new Response('Unauthorized', {status:401}); }
  if (!batch.configured) return Response.json({configured:false,sent:0});
  let sent=0,failed=0;
  for (const job of batch.jobs) {
    let ok=false,code='network';
    try {
      const r=await fetch('https://api.resend.com/emails',{method:'POST',signal:AbortSignal.timeout(10000),headers:{Authorization:`Bearer ${batch.key}`,'Content-Type':'application/json','Idempotency-Key':`liftcare-access-${job.id}`},body:JSON.stringify({from:batch.from,to:[batch.to],subject:'LiftCare: richiesta di accesso da approvare',text:`L’account ${job.email} ha confermato l’email e richiede accesso a LiftCare.\n\nApri https://anto287.github.io/manutenzione-muletti/ e seleziona Approva utenti.\n\nFino alla tua approvazione, il backend blocca dati e foto.`})});
      ok=r.ok;code=`provider_${r.status}`;
    } catch { code='network'; }
    try {await rpc('finish_email_job',{job_token:token,job_id:job.id,succeeded:ok,error_code:ok?null:code});}catch{failed++;continue;}
    if(ok)sent++;else failed++;
  }
  return Response.json({configured:true,sent,failed,budget_blocked:!!batch.budget_blocked});
});
