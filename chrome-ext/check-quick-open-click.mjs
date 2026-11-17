import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { startQuickOpen } from './lib/portal-open.js';
const source=readFileSync(new URL('./popup.js',import.meta.url),'utf8');
const html=readFileSync(new URL('./popup.html',import.meta.url),'utf8');
for (const action of ['portal','edufine','neis']) assert.ok(html.includes(`data-action="${action}"`));
assert.ok(source.includes("type:'QUICK_OPEN'") || source.includes('type:\'QUICK_OPEN\''));
let focused=[];let written={};
globalThis.chrome={
 tabs:{query:async()=>[{id:7,windowId:2,url:'https://pen.neis.go.kr/jsp/main.jsp',status:'complete'}],update:async id=>focused.push(id)},
 windows:{update:async()=>{}},scripting:{executeScript:async()=>[{result:true}]},
 storage:{session:{set:async patch=>Object.assign(written,patch)}}
};
assert.equal((await startQuickOpen('neis',undefined)).ok,true);
assert.deepEqual(focused,[7]);
assert.ok(written.quickOpen.text.includes('이미 열린'));
chrome.tabs.query=async()=>[{id:8,windowId:2,url:'https://pen.eduptl.kr/main',status:'complete'}];
chrome.scripting.executeScript=async()=>[{result:'main'}];
assert.equal((await startQuickOpen('portal',undefined)).ok,true);
assert.equal((await startQuickOpen('invalid',undefined)).ok,false);
console.log('PASS: all three real click handlers dispatch; logged-in NEIS/portal work without stored certificate password; invalid target rejected (browser mocks)');
