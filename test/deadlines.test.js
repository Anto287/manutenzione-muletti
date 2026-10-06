import test from 'node:test';
import assert from 'node:assert/strict';
import {blank,validateBackup} from '../src/domain.js';
import {deadlineDue} from '../src/deadlines.js';
const machine={id:'v1',name:'Auto',type:'car',model:'Test',serial:'',plate:'ABC',power:'Diesel',unit:'km',reading:100};
const deadline={id:'d1',vehicleId:'v1',kind:'insurance',dueDate:'2026-10-06',notify:true,notes:''};
test('deadline dates distinguish due today from overdue across months and leap years',()=>{
 assert.deepEqual(deadlineDue(deadline,'2026-10-06'),{days:0,status:'In scadenza'});
 assert.deepEqual(deadlineDue(deadline,'2026-10-07'),{days:-1,status:'Scaduto'});
 assert.equal(deadlineDue({...deadline,dueDate:'2028-03-01'},'2028-02-28').days,2);
 assert.equal(deadlineDue({...deadline,dueDate:'2027-01-01'},'2026-12-01').status,'Regolare');
});
test('backups preserve deadlines and email opt-out; legacy v2 defaults remain compatible',()=>{
 const data={...blank(),vehicles:[machine],deadlines:[deadline],emailNotifications:false};
 assert.equal(validateBackup(data),data);assert.equal(validateBackup(JSON.parse(JSON.stringify(data))).emailNotifications,false);
 const {deadlines,emailNotifications,...old}=data;const restored=validateBackup(old);assert.deepEqual(restored.deadlines,[]);assert.equal(restored.emailNotifications,true);assert.equal(old.deadlines,undefined);
});
test('invalid or duplicate deadlines and cross-vehicle references are rejected',()=>{
 for(const invalid of [null,{...deadline,dueDate:'2026-02-30'},{...deadline,vehicleId:'other'},{...deadline,notify:'true'},{...deadline,kind:'arbitrary'}])assert.throws(()=>validateBackup({...blank(),vehicles:[machine],deadlines:[invalid]}));
 assert.throws(()=>validateBackup({...blank(),vehicles:[machine],deadlines:[deadline,{...deadline,id:'d2'}]}));
});
