import assert from 'node:assert/strict';
import { prepareRoute, runNeisRoute } from './lib/neis-route.js';
const preset={Label:'시간외',Time:'18:00~20:00',Reason:'수업 준비',LineName:'테스트 결재선'};
const job=prepareRoute(preset,{start:'2026-11-03',end:'2026-11-03'});
assert.equal(job.kind,'overtime');
for(const p of [{...preset,Time:'종일'},{...preset,Time:'25:00~26:00'},{...preset,Time:'20:00~18:00'},{...preset,LineName:''},{...preset,Label:'병가'}])assert.throws(()=>prepareRoute(p,{}));
assert.throws(()=>prepareRoute({...preset,Label:'출장'},{}));
assert.throws(()=>prepareRoute({...preset,Label:'연가'},{}));
const base='edu/ga/srv/mym/mm/',draftId='edu/cm/wam/woa/pm/wam_woapm07_p00',lineId='edu/cm/wam/woa/pm/wam_woapm07_p02';
let apps=[], calls=[], reject=false;
const ctrl={};
const form={app:{id:base+'srv_mymmm02_p00'},lookup(id){
  if(id==='grdMain')return {dataSet:{getRowCount:()=>1}};
  if(id==='btnAprvDmnd')return {click(){calls.push('approval');apps.push(draft);}};
  if(id==='dtiMtWorkH')return {value:'2'};if(id==='dtiMtWorkM')return {value:'0'};
  return ctrl[id] ||= {value:'',putValue(value){this.value=reject&&id==='txaMtWorkRsnCn'?'rejected':value;}};
}};
const draft={app:{id:draftId},lookup(id){
  if(id==='btnSelectMySancr')return {click(){calls.push('line');apps.push(line);}};
  if(id==='grdSancr')return {dataSet:{getRowCount:()=>2}};
  throw Error('Unexpected control (including submit): '+id);
}};
const line={app:{id:lineId},lookup(id){
  if(id==='grd3')return {dataSet:{getRowCount:()=>1,getValue:()=>job.line},selectRows(indices){assert.equal(indices[0],0);calls.push('select');}};
  if(id==='grd2')return {dataSet:{getRowCount:()=>1}};
  if(id==='btn4')return {click(){calls.push('apply');apps=apps.filter(a=>a!==line);}};
}};
const list={app:{id:base+'srv_mymmm02_m00'},lookup(id){assert.equal(id,'btnAply');return {click(){calls.push('open');apps.push(form);}};}};
globalThis.window={cpr:{core:{Platform:{INSTANCE:{getAllRunningAppInstances:()=>apps}}}}};
const timer=globalThis.setTimeout;globalThis.setTimeout=callback=>{callback();return 0;};
try {
  apps=[list];assert.equal((await runNeisRoute(job)).ok,true);
  assert.deepEqual(calls,['open','approval','line','select','apply']);
  apps=[list,form];calls=[];assert.equal((await runNeisRoute(job)).ok,false);assert.equal(calls.length,0);
  apps=[list];calls=[];reject=true;const result=await runNeisRoute(job);assert.equal(result.ok,false);assert.equal(result.step,'입력값 검증');assert.deepEqual(calls,['open']);
}finally{globalThis.setTimeout=timer;}
console.log('PASS: route validation; overtime application through approval-line selection; no final submission; busy form and input mismatch stop execution (mock controls)');
