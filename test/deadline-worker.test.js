import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
const source=stripTypeScriptTypes((await readFile(new URL('../backend/supabase/functions/deadline-email/index.ts',import.meta.url),'utf8')).replace(/^import nodemailer.*\n/,''));
const job={id:1,to:'owner@example.test',test:false,items:[{vehicle:'Auto <script>',plate:'AB123',kind:'insurance',date:'2026-10-13'}]};
function worker(send,error,batch={configured:true,email:'sender@gmail.com',password:'vault-only-secret',jobs:[job]}){
 let handler;const finishes=[],smtp=[];
 const fetch=async(url,opts)=>{if(url.endsWith('claim_deadline_jobs')){if(error)return Response.json({}, {status:401});return Response.json(batch)}finishes.push(JSON.parse(opts.body));return new Response('null')};
 vm.runInNewContext(source,{Deno:{serve:f=>handler=f,env:{get:n=>n==='SUPABASE_URL'?'https://backend.test':'service-secret'}},fetch,Response,AbortSignal,Error,JSON,String,nodemailer:{createTransport:opts=>{smtp.push(opts);return {sendMail:send,close(){}}}}});return {handler,finishes,smtp};
}
const request=token=>new Request('https://backend.test/fn',{method:'POST',headers:token?{'x-liftcare-job':token}:{}});
test('reminder worker denies missing/invalid job tokens before SMTP; unset configuration cannot send',async()=>{
 const denied=worker(()=>{throw Error('SMTP reached')},true);assert.equal((await denied.handler(request())).status,401);assert.equal((await denied.handler(request('invalid'))).status,401);assert.equal(denied.smtp.length,0);
 const unset=worker(()=>{throw Error('SMTP reached')},false,{configured:false});assert.deepEqual(await (await unset.handler(request('valid'))).json(),{configured:false,sent:0});assert.equal(unset.smtp.length,0);
});
test('email goes only to its account owner and contains safe HTML, text, date and vehicle, without credentials',async()=>{
 const mails=[];const w=worker(async mail=>{mails.push(mail);return {accepted:[mail.to],messageId:'provider-id'}});
 const result=await w.handler(request('valid'));assert.deepEqual(await result.json(),{configured:true,sent:1,failed:0,budget_blocked:false});assert.equal(mails[0].to,job.to);assert.equal(mails[0].from.address,'sender@gmail.com');assert.match(mails[0].html,/Auto &lt;script&gt;/);assert.match(mails[0].text,/Assicurazione: 13\/10\/2026/);assert.ok(!mails[0].html.includes('vault-only-secret'));assert.equal(w.smtp[0].secure,true);assert.equal(w.smtp[0].port,465);assert.equal(w.finishes[0].outcome,'sent');
});
test('only definitive temporary SMTP failures retry; uncertain delivery is never automatically retried',async()=>{
 for(const [error,outcome,code] of [[{code:'EAUTH'},'failed','smtp_auth'],[{responseCode:451},'retry','smtp_temporary'],[{responseCode:550},'failed','smtp_rejected'],[{code:'ETIMEDOUT'},'uncertain','smtp_uncertain']]){
  const w=worker(async()=>{throw error});await w.handler(request('valid'));assert.equal(w.finishes[0].outcome,outcome);assert.equal(w.finishes[0].error_code,code);
 }
});
