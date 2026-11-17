import {prepareCertDialog, submitCertPassword} from './portal-open.js';
const HOME='https://mail.korea.kr/';
export function inspectOfficialMail(open=false){
 if(location.origin!=='https://mail.korea.kr')return {state:'wrong-origin'};
 const visible=el=>!!el?.getClientRects().length;
 const controls=[...document.querySelectorAll('a,button')].filter(visible);
 const text=el=>(el.innerText||el.textContent||'').replace(/\s+/g,'').trim();
 if(controls.some(el=>text(el)==='로그아웃'))return {state:'logged-in'};
 if(visible(document.querySelector('#kc_dialog_default')))return {state:'supported-certificate'};
 const login=controls.filter(el=>text(el)==='인증서로그인');
 if(login.length!==1)return {state:'unknown'};
 if(open)login[0].click();
 return {state:open?'certificate-requested':'login'};
}
export function submitOfficialMailPassword(password){
 if(location.origin!=='https://mail.korea.kr')return false;
 const dialog=document.querySelector('#kc_dialog_default');
 const input=dialog?.querySelector('input[name=certPassword]');
 const button=dialog?.querySelector('button.kc-btn-blue');
 if(!dialog?.getClientRects().length || !input || !button || input.disabled || button.disabled)return false;
 const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;
 if(!setter)return false;
 setter.call(input,password);input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));button.click();return true;
}
let busy=false;
export async function openOfficialMail(password){
 if(busy)return {ok:false,error:'공직메일 로그인을 진행 중입니다.'};busy=true;
 const pause=ms=>new Promise(r=>setTimeout(r,ms));
 try{
  const tabs=await chrome.tabs.query({url:HOME+'*'});
  let tab=tabs.find(t=>t.active)||tabs[0];
  if(tab){await chrome.tabs.update(tab.id,{active:true});await chrome.windows.update(tab.windowId,{focused:true});}
  else tab=await chrome.tabs.create({url:HOME,active:true});
  const inspect=async open=>{
   const current=await chrome.tabs.get(tab.id);
   if(new URL(current.url||HOME).origin!=='https://mail.korea.kr')return {state:'wrong-origin'};
   const result=await chrome.scripting.executeScript({target:{tabId:tab.id},world:'ISOLATED',func:inspectOfficialMail,args:[open]});return result[0]?.result||{state:'unknown'};
  };
  let state;
  for(let i=0;i<20;i++){try{state=await inspect(false);}catch(_){state={state:'loading'};}if(['login','logged-in','supported-certificate'].includes(state.state))break;await pause(400);}
  if(state?.state==='logged-in')return {ok:true,message:'로그인된 공직메일로 이동했습니다.'};
  if(state?.state==='login')await inspect(true);
  for(let i=0;i<16;i++){await pause(400);state=await inspect(false);if(['supported-certificate','logged-in','wrong-origin'].includes(state.state))break;}
  if(state.state==='logged-in')return {ok:true,message:'공직메일 로그인 완료'};
  if(state.state!=='supported-certificate')return {ok:true,needsUser:true,message:'공직메일 인증서 로그인을 열었습니다. 별도 인증서 창은 직접 진행해주세요. 자동 입력 가능한 웹 인증서 창은 확인되지 않았습니다.'};
  if(!password)return {ok:true,needsUser:true,message:'인증서 창을 열었습니다. 설정 → 인증서 비밀번호에서 저장하거나 열린 창에 직접 입력하세요.'};
  const {officialMailAttemptAt=0}=await chrome.storage.session.get('officialMailAttemptAt');
  if(Date.now()-officialMailAttemptAt<30000)return {ok:false,error:'인증서 비밀번호를 반복 입력하지 않습니다. 인증서 창의 결과를 확인하세요.'};
  const {certHint=''}=await chrome.storage.local.get('certHint');
  const prep=await chrome.scripting.executeScript({target:{tabId:tab.id},func:prepareCertDialog,args:[certHint]});
  if(!prep[0]?.result?.ok)return {ok:false,error:prep[0]?.result?.error||'인증서를 확인하지 못했습니다.'};
  await chrome.storage.session.set({officialMailAttemptAt:Date.now()});
  const sent=await chrome.scripting.executeScript({target:{tabId:tab.id},func:submitCertPassword,args:[password]});
  if(sent[0]?.result!==true)return {ok:false,error:sent[0]?.result?.error||'인증서 비밀번호 입력에 실패했습니다.'};
  for(let i=0;i<20;i++){await pause(500);if((await inspect(false)).state==='logged-in')return {ok:true,message:'공직메일 로그인 완료'};}
  return {ok:true,needsUser:true,message:'인증서 비밀번호를 한 번 입력했습니다. 로그인 완료가 확인되지 않아 추가 입력을 중단했습니다. 공직메일 창을 확인하세요.'};
 }catch(_){return {ok:false,error:'공직메일 연결을 확인하지 못했습니다. 열린 공직메일 화면과 확장의 사이트 접근 권한을 확인하세요.'};}finally{busy=false;}
}
