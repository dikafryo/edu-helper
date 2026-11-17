import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const html=readFileSync(new URL('./popup.html',import.meta.url),'utf8');
const nodes=[];
class Element {
  constructor(attrs=''){this.listeners={};this.dataset={};this.style={};this.value='';this.classList={toggle(){},add(){},remove(){}};this.children=[];
    for(const m of attrs.matchAll(/([\w-]+)="([^"]*)"/g)){this[m[1]]=m[2];if(m[1].startsWith('data-'))this.dataset[m[1].slice(5)]=m[2];}}
  addEventListener(type,fn){(this.listeners[type]||=[]).push(fn);}
  setAttribute(key,value){this[key]=value;} removeAttribute(key){delete this[key];}
  appendChild(node){this.children.push(node);return node;} replaceChildren(...nodes){this.children=nodes;}
  querySelector(selector){return this.children.find(n=>n.tagName===selector)||this.appendChild(Object.assign(new Element(),{tagName:selector}));}
  querySelectorAll(){return [];} focus(){}
}
for(const m of html.matchAll(/<(?:button|div|p|section|input|textarea|select)[^>]*>/g))nodes.push(new Element(m[0]));
globalThis.document={body:Object.assign(new Element(),{firstChild:null}),createElement:()=>new Element(),getElementById:id=>nodes.find(n=>n.id===id)||null,
 querySelectorAll:selector=>nodes.filter(n=>selector.split(',').some(s=>s.trim().startsWith('.')?String(n.class||'').split(' ').includes(s.trim().slice(1)):s.trim()==='[data-workflow]'&&n.dataset.workflow))};
globalThis.window={};
const sent=[];
globalThis.chrome={runtime:{sendMessage:async msg=>{sent.push(msg);return msg.type==='VAULT_STATUS'?{ok:true,pinLockEnabled:true,unlocked:true}:msg.type==='AI_STATUS'?{ok:true}: {ok:true};}},storage:{local:{get:async()=>({dutyPresets:[]})},session:{get:async()=>({})},onChanged:{addListener(){}}}};
const interval=globalThis.setInterval;globalThis.setInterval=()=>0;
try{
 await import('./popup.js');
 for(const act of ['openPortal','openEdufine','openNeis']){
  const button=nodes.find(n=>n.dataset.act===act);
  assert.ok(button.listeners.click?.length,act+' has no handler');
  for(const handler of button.listeners.click)await handler();
 }
 assert.deepEqual(sent.filter(m=>m.type==='QUICK_OPEN').map(m=>m.target),['portal','edufine','neis']);
 console.log('PASS: complete popup module graph initializes and all three buttons dispatch (DOM/Chrome mocks)');
}finally{globalThis.setInterval=interval;}
