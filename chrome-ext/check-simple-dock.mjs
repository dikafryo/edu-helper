import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('./dock.html',import.meta.url),'utf8');
assert.deepEqual([...html.matchAll(/data-act="([^"]+)"/g)].map(m=>m[1]),['noticeDraft','proofread','travelApplication','todoAdd']);
assert.equal((html.match(/<input\b/g)||[]).length,1);
assert.equal((html.match(/contenteditable="true"/g)||[]).length,1);
assert.equal((html.match(/<textarea\b/g)||[]).length,0);
assert.ok(html.includes('>제목복사<')&&html.includes('>본문복사<'));
const code=readFileSync(new URL('./dock.js',import.meta.url),'utf8');
const calls=[],statuses=[];let handler,prepared=0;
const c=vm.createContext({document:{getElementById:()=>({addEventListener:(event,fn)=>handler=fn})},chrome:{runtime:{sendMessage:async m=>{calls.push(m);return m.type==='VAULT_STATUS'?{ok:true,pinLockEnabled:true,unlocked:true}:{ok:true,message:'열림'};}}},prepareNotice:async()=>prepared++,currentNotice:()=>({title:'행사 안내',body:'1. 관련: 부서-1'}),proofreadNotice:()=>({ok:true,text:'검사 결과'}),setStatus:text=>statuses.push(text)});
vm.runInContext(code.slice(code.indexOf("document.getElementById('actions').addEventListener"),code.indexOf('async function syncPos()')),c);
for(const action of ['noticeDraft','proofread','travelApplication','todoAdd']){
 const button={dataset:{act:action},disabled:false};await handler({target:{closest:()=>button}});assert.equal(button.disabled,false);
}
assert.equal(prepared,1);assert.ok(statuses.includes('검사 결과'));
assert.ok(calls.some(m=>m.type==='OPEN_WORK_PAGE'&&m.page==='trip'));
const calendar=calls.find(m=>m.type==='GCAL_OPEN');assert.equal(calendar.title,'행사 안내');assert.equal(calendar.details,'1. 관련: 부서-1');
assert.ok(!calls.some(m=>m.type==='TODO_FROM_TEXT'));
console.log('PASS (mock): four actions, two edit fields, two copy controls, integrated notice and Google Calendar draft route');
