import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const code=readFileSync(new URL('./background.js',import.meta.url),'utf8');
let local={pinLockEnabled:true},session={},badge='';const alarms=[];
const chrome={storage:{local:{get:async()=>({...local}),set:async patch=>Object.assign(local,patch)},session:{get:async()=>({...session}),set:async patch=>Object.assign(session,patch),remove:async key=>delete session[key]}},action:{setBadgeText:async p=>badge=p.text,setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},alarms:{create:async(name,info)=>alarms.push({name,...info})}};
function worker(){const c=vm.createContext({chrome,Date,UNLOCK_MS_DEFAULT:600000});vm.runInContext(code.slice(code.indexOf('let memSession ='),code.indexOf('async function wipeVaultStorage')),c);return c;}
let c=worker();vm.runInContext('memSession={pinVerifiedAt:Date.now(),certPassword:"test-only"}',c);
const before=Date.now();await c.markUnlocked(21600000);assert.ok(local.penUnlockedUntil>=before+21600000);assert.equal(badge,'ON');
c=worker();await c.syncPinBadge();assert.equal(badge,'ON');assert.equal(vm.runInContext('memSession.certPassword',c),'test-only');
await c.markUnlocked(86400000);assert.ok(local.penUnlockedUntil>Date.now()+86390000);
await c.lockNow();await c.syncPinBadge();assert.equal(badge,'');assert.equal(session.penPinSession,undefined);
c=worker();await c.restorePinSession();assert.equal(vm.runInContext('memSession',c),null);
session.penPinSession={until:Date.now()-1,session:{pinVerifiedAt:1}};local.penUnlockedUntil=session.penPinSession.until;
await c.restorePinSession();assert.equal(vm.runInContext('memSession',c),null);
session={};local.penUnlockedUntil=Date.now()+86400000;c=worker();await c.syncPinBadge();assert.equal(badge,'');
console.log('PASS: 6h/24h duration, worker wake restoration, explicit lock purge, expiry and browser-session end');
