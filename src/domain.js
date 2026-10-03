export const today=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`};
export function addMonths(date,n){const [y,m,d]=date.split('-').map(Number);const target=new Date(y,m-1+n,1);const last=new Date(target.getFullYear(),target.getMonth()+1,0).getDate();return `${target.getFullYear()}-${String(target.getMonth()+1).padStart(2,'0')}-${String(Math.min(d,last)).padStart(2,'0')}`}
export function due(task,vehicle,date=today()){
 const hours=task.hours?task.lastHours+task.hours:null;
 const day=task.months?addMonths(task.lastDate,task.months):null;
 const remaining=hours===null?null:hours-vehicle.hours;
 const days=day===null?null:Math.round((Date.parse(day)-Date.parse(date))/86400000);
 const overdue=(remaining!==null&&remaining<=0)||(days!==null&&days<=0);
 const soon=(remaining!==null&&remaining<=Math.min(50,task.hours*.1))||(days!==null&&days<=30);
 return {hours,day,remaining,days,status:overdue?'Scaduto':soon?'In scadenza':'Regolare'};
}
export function complete(data,vehicleId,taskIds,entry){
 const vehicle=data.vehicles.find(v=>v.id===vehicleId);
 if(!vehicle||!taskIds.length)throw Error('Seleziona almeno un intervento.');
 if(!Number.isFinite(entry.hours)||entry.hours<vehicle.hours)throw Error('Le ore non possono essere inferiori al contatore attuale.');
 if(!entry.date||entry.date>today())throw Error('Inserisci una data valida, non futura.');
 const tasks=data.tasks.filter(t=>t.vehicleId===vehicleId&&taskIds.includes(t.id));
 if(tasks.length!==taskIds.length)throw Error('Interventi non validi.');
 if(tasks.some(t=>entry.date<t.lastDate||entry.hours<t.lastHours))throw Error('La registrazione precede l’ultimo intervento del piano.');
 const result=structuredClone(data);result.vehicles.find(v=>v.id===vehicleId).hours=entry.hours;
 result.tasks.filter(t=>taskIds.includes(t.id)).forEach(t=>{t.lastHours=entry.hours;t.lastDate=entry.date});
 result.history.unshift({...entry,id:crypto.randomUUID(),vehicleId,vehicleName:vehicle.name,items:tasks.map(t=>({name:t.name,part:t.part}))});return result;
}
export function validateBackup(d){
 const str=x=>typeof x==='string';const identifier=x=>str(x)&&/^[a-zA-Z0-9_-]+$/.test(x);const num=x=>Number.isFinite(x)&&x>=0;
 const date=x=>str(x)&&/^\d{4}-\d{2}-\d{2}$/.test(x)&&Number.isFinite(Date.parse(x))&&new Date(x).toISOString().slice(0,10)===x;
 if(d?.version!==1||!Array.isArray(d.vehicles)||!Array.isArray(d.tasks)||!Array.isArray(d.history))throw Error('Backup non valido.');
 if(d.vehicles.some(v=>!identifier(v.id)||!str(v.name)||!str(v.model)||!str(v.serial)||!str(v.power)||!num(v.hours)))throw Error('Anagrafica non valida.');
 const ids=new Set(d.vehicles.map(v=>v.id));
 if(ids.size!==d.vehicles.length||new Set(d.tasks.map(t=>t.id)).size!==d.tasks.length)throw Error('Identificativi duplicati.');
 if(d.tasks.some(t=>!identifier(t.id)||!ids.has(t.vehicleId)||!str(t.name)||!str(t.part)||!num(t.hours)||!num(t.months)||!Number.isInteger(t.months)||!(t.hours||t.months)||!num(t.lastHours)||!date(t.lastDate)||t.lastHours>d.vehicles.find(v=>v.id===t.vehicleId).hours))throw Error('Piano non valido.');
 if(d.history.some(h=>!identifier(h.id)||!str(h.vehicleName)||!ids.has(h.vehicleId)||!date(h.date)||!num(h.hours)||!num(h.cost)||!str(h.technician)||!str(h.notes)||!Array.isArray(h.items)||h.items.some(i=>!str(i.name)||!str(i.part))))throw Error('Storico non valido.');
 return d;
}
export const blank=()=>({version:1,vehicles:[],tasks:[],history:[]});
