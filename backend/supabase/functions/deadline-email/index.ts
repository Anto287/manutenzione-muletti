import nodemailer from 'npm:nodemailer@10.0.15';

// Server-only worker. Tokens and SMTP credentials never reach the browser or logs.
const url='https://anto287.github.io/manutenzione-muletti/';
const types:Record<string,string>={revision:'Revisione',tax:'Bollo',insurance:'Assicurazione'};
const escape=(s:unknown)=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
function message(job:any){
 const rows=job.items.map((i:any)=>({vehicle:i.vehicle+(i.plate?' · '+i.plate:''),kind:types[i.kind],date:i.date.split('-').reverse().join('/')}));
 const title=job.test?'Il tuo promemoria LiftCare funziona':'Le scadenze dei tuoi mezzi';
 return {subject:job.test?'LiftCare: prova promemoria email':`LiftCare: ${rows.length} ${rows.length===1?'scadenza da controllare':'scadenze da controllare'}`,
 text:`${title}\n\n${job.test?'Questa è una prova richiesta dal tuo account. Riceverai qui i promemoria per revisione, bollo e assicurazione.':rows.map((r:any)=>`${r.vehicle}\n${r.kind}: ${r.date}`).join('\n\n')}\n\nApri LiftCare: ${url}\nSeleziona Scadenze per aggiornare le date dopo il rinnovo.\nPuoi disattivare questi avvisi da Account e backup > I miei promemoria email.\n\nPromemoria richiesti dal tuo account. Nessuna pubblicità.`,
 html:`<!doctype html><html lang="it"><head><meta charset="utf-8"><title>${title}</title></head><body style="margin:0;background:#f3f7f5;font-family:Arial,sans-serif;color:#183c3b"><table role="presentation" width="100%"><tr><td align="center" style="padding:24px 12px"><table role="presentation" width="100%" style="max-width:560px;background:white;border-radius:16px"><tr><td style="padding:28px"><p style="font-size:18px;font-weight:bold;color:#17665f">LiftCare</p><h1 style="font-size:24px">${title}</h1>${job.test?'<p>Questa è una prova richiesta dal tuo account. Qui riceverai i promemoria di revisione, bollo e assicurazione.</p>':rows.map((r:any)=>`<div style="border-top:1px solid #dbe7e2;padding:16px 0"><h2 style="font-size:18px;margin:0 0 8px">${escape(r.vehicle)}</h2><p style="margin:0">${r.kind} · <strong>${r.date}</strong></p></div>`).join('')}<p><a href="${url}" style="color:#17665f;font-weight:bold">Apri LiftCare e controlla le scadenze</a></p><p style="font-size:14px;color:#506c67">Aggiorna la data quando rinnovi il documento. Per disattivare gli avvisi: Account e backup → I miei promemoria email.</p><p style="font-size:12px;color:#506c67">Promemoria richiesti dal tuo account. Nessuna pubblicità.</p></td></tr></table></td></tr></table></body></html>`};
}
function failure(error:any){
 if(error.code==='EAUTH')return {outcome:'failed',code:'smtp_auth'};
 if(error.responseCode>=400&&error.responseCode<500)return {outcome:'retry',code:'smtp_temporary'};
 if(error.responseCode>=500)return {outcome:'failed',code:'smtp_rejected'};
 // These errors occur before a message can be accepted by the SMTP server.
 if(['EDNS','ECONNREFUSED','ETLS'].includes(error.code)||error.command==='CONN')return {outcome:'retry',code:'smtp_connect'};
 return {outcome:'uncertain',code:'smtp_uncertain'};
}
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 const token=req.headers.get('x-liftcare-job');if(!token||token.length>200)return new Response('Unauthorized',{status:401});
 const base=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 async function rpc(name:string,body:unknown){const r=await fetch(`${base}/rest/v1/rpc/${name}`,{method:'POST',signal:AbortSignal.timeout(10000),headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body)});if(!r.ok)throw Error('rpc_failed');const text=await r.text();return text?JSON.parse(text):null}
 let batch;const probing=req.headers.get('x-liftcare-probe')==='smtp';try{batch=await rpc(probing?'check_deadline_worker':'claim_deadline_jobs',{job_token:token})}catch{return new Response('Unauthorized',{status:401})}
 if(probing){const probe=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,connectionTimeout:10000,greetingTimeout:10000,socketTimeout:10000,logger:false,debug:false});try{await probe.verify();return Response.json({smtp_available:true})}catch{return Response.json({smtp_available:false},{status:502})}finally{probe.close()}}
 if(!batch.configured)return Response.json({configured:false,sent:0});
 const transporter=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,auth:{user:batch.email,pass:batch.password},connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000,tls:{minVersion:'TLSv1.2'},logger:false,debug:false});
 let sent=0,failed=0;
 for(const job of batch.jobs){let outcome='sent',code:string|null=null,provider:string|null=null;
  try{const result=await transporter.sendMail({from:{name:'LiftCare',address:batch.email},to:job.to,messageId:`<liftcare-deadline-${job.id}@gmail.com>`,...message(job),disableFileAccess:true,disableUrlAccess:true});if(!result.accepted?.length){outcome='failed';code='smtp_rejected'}else provider=result.messageId}
  catch(error){const f=failure(error);outcome=f.outcome;code=f.code}
  try{await rpc('finish_deadline_job',{job_token:token,job_id:job.id,outcome,error_code:code,provider_id:provider});if(outcome==='sent')sent++;else failed++}catch{failed++}
 }
 transporter.close();return Response.json({configured:true,sent,failed,budget_blocked:!!batch.budget_blocked});
});
