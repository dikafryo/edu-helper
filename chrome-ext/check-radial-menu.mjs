import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const listeners={},calls=[];let hosts=[],allow=true;
class Element {
 constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.style={};this.isConnected=true;this.map={};this.textContent='';this.disabled=false;this.readOnly=false;}
 append(...els){this.children.push(...els);for(const el of els){el.parentElement=this;if(el.id==='pen-radial-menu')hosts.push(el);}}
 appendChild(el){this.append(el);}
 attachShadow(){this.shadow=new Element();return this.shadow;}
 setAttribute(){} focus(){} remove(){this.isConnected=false;}
 set innerHTML(value){this._html=value;if(value.includes('data-apply'))for(const key of ['[data-close]','.message','.preview','[data-apply]','[data-undo]'])this.map[key]=new Element();}
 get innerHTML(){return this._html||'';}
 querySelector(selector){return this.map[selector] || (selector==='button'?this.children.find(c=>c.tagName==='BUTTON'):null);}
 closest(){return this.tagName==='TEXTAREA'?this:null;}
 dispatchEvent(){return true;}
}
class TextArea extends Element {constructor(){super('textarea');this._value='';}set value(v){this._value=v;}get value(){return this._value;}closest(selector){return selector==='[contenteditable="false"]'?null:this;}}
const document={createElement:tag=>new Element(tag),documentElement:new Element(),addEventListener:(name,fn)=>listeners[name]=fn};
const context=vm.createContext({document,innerWidth:1000,innerHeight:800,HTMLTextAreaElement:TextArea,InputEvent:class{},Event:class{},chrome:{runtime:{sendMessage:async msg=>{calls.push(msg);return allow?{ok:true}:{ok:false,error:'PIN 잠김'};}}}});
vm.runInContext(readFileSync(new URL('./lib/proofread-core.js',import.meta.url),'utf8'),context);
vm.runInContext(readFileSync(new URL('./radial-menu.js',import.meta.url),'utf8'),context);
const editor=new TextArea();editor.value='1. 내용\n  가. 항목\n 나. 몇일';
let prevented=false;
function event(shift=true){return {isTrusted:true,shiftKey:shift,target:editor,clientX:990,clientY:790,preventDefault(){prevented=true;},stopPropagation(){}};}
listeners.contextmenu(event(false));assert.equal(hosts.length,0);assert.equal(prevented,false);
listeners.contextmenu({...event(),isTrusted:false});assert.equal(hosts.length,0);
listeners.contextmenu(event());assert.equal(prevented,true);
let wheel=hosts.at(-1).shadow.children[0];
assert.deepEqual(wheel.children.map(c=>c.textContent),['업무포털','나이스','K에듀파인','출장','공문안내','공문점검','닫기']);
assert.equal(wheel.style.left,'700px');assert.equal(wheel.style.top,'500px');
await wheel.children[5].onclick();let box=hosts.at(-1).shadow.children[0];
assert.equal(calls.at(-1).action,'proofread');assert.equal(box.map['[data-apply]'].disabled,false);
await box.map['[data-apply]'].onclick();assert.equal(editor.value,'1. 내용\n  가. 항목\n  나. 며칠');
box.map['[data-undo]'].onclick();assert.equal(editor.value,'1. 내용\n  가. 항목\n 나. 몇일');
listeners.contextmenu(event());await hosts.at(-1).shadow.children[0].children[5].onclick();box=hosts.at(-1).shadow.children[0];
editor.value+=' 변경';await box.map['[data-apply]'].onclick();assert.ok(box.map['.message'].textContent.includes('원문이 바뀌었습니다'));
allow=false;listeners.contextmenu(event());await hosts.at(-1).shadow.children[0].children[5].onclick();box=hosts.at(-1).shadow.children[0];assert.equal(box.map['[data-apply]'].disabled,true);assert.equal(box.map['.message'].textContent,'PIN 잠김');
allow=true;
for(let i=0;i<5;i++){listeners.contextmenu(event());await hosts.at(-1).shadow.children[0].children[i].onclick();assert.equal(calls.at(-1).action,['portal','neis','edufine','travel','notice'][i]);}
listeners.contextmenu(event());listeners.keydown({key:'Escape',preventDefault(){}});assert.equal(hosts.at(-1).isConnected,false);
console.log('PASS (mock DOM): Shift/trusted-event gating, six actions, viewport clamping, PIN denial, text edit/undo, stale-source rejection and Escape dismissal');
