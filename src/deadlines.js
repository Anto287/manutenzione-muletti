export const deadlineTypes={revision:'Revisione',tax:'Bollo',insurance:'Assicurazione'};
export function deadlineDue(item,day){
  const days=Math.round((Date.parse(item.dueDate)-Date.parse(day))/86400000);
  return {days,status:days<0?'Scaduto':days<=30?'In scadenza':'Regolare'};
}
export function validateDeadlines(items,vehicles){
  if(!Array.isArray(items))throw Error('Scadenze non valide.');
  const ids=new Set(),pairs=new Set(),owners=new Set(vehicles.map(v=>v.id));
  for(const d of items){const key=d?.vehicleId+'|'+d?.kind;if(!d||typeof d.id!=='string'||!/^[a-zA-Z0-9_-]+$/.test(d.id)||ids.has(d.id)||pairs.has(key)||!owners.has(d.vehicleId)||!Object.hasOwn(deadlineTypes,d.kind)||typeof d.dueDate!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(d.dueDate)||!Number.isFinite(Date.parse(d.dueDate))||new Date(d.dueDate).toISOString().slice(0,10)!==d.dueDate||typeof d.notify!=='boolean'||typeof d.notes!=='string'||d.notes.length>1000)throw Error('Scadenze non valide.');ids.add(d.id);pairs.add(key)}
  return items;
}
