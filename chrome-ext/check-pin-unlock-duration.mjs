import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('./background.js',import.meta.url),'utf8');
let valid=true,duration=0,config={pinLockEnabled:true,pinVerify:{},unlockMs:600000};
const ctx=vm.createContext({Date,UNLOCK_MS_DEFAULT:600000,pinAttemptBlocked:async()=>'',verifyPinHash:async()=>valid,recordPinFailure:async()=>'PIN 오류',markUnlocked:async ms=>{duration=ms;return Date.now()+ms;},chrome:{storage:{local:{get:async()=>config}}}});
vm.runInContext('let memSession=null;'+source.slice(source.indexOf('async function handlePinUnlock('),source.indexOf('async function handleVaultSave(')),ctx);
for(const ms of [21600000,86400000]){const r=await ctx.handlePinUnlock({pin:'test',unlockMs:ms});assert.equal(r.ok,true);assert.equal(r.unlocked,true);assert.equal(duration,ms);assert.ok(r.unlockedUntil>Date.now()+ms-1000);}
valid=false;duration=0;assert.equal((await ctx.handlePinUnlock({pin:'wrong',unlockMs:86400000})).ok,false);assert.equal(duration,0);
config={pinLockEnabled:false};assert.equal((await ctx.handlePinUnlock({pin:'test'})).ok,false);
console.log('PASS: successful PIN applies selected 6h/24h; invalid PIN and missing setup never unlock');
