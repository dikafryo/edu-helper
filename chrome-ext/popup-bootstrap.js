// Keep this loader independent of feature imports so startup errors remain visible.
const health=document.createElement('div');
health.id='startupHealth';health.setAttribute('role','status');
health.style.cssText='padding:10px 14px;background:#fff4da;color:#493710;font:12px/1.6 sans-serif;white-space:pre-wrap;';
const version=chrome.runtime.getManifest().version;
const show=text=>{health.textContent=`교직원 업무도우미 ${version} · ${text}`;document.body.prepend(health);};
const message=e=>String(e?.message||e||'알 수 없는 오류').replace(/https?:\/\/\S+/g,'[주소 생략]').slice(0,350);
window.addEventListener('error',event=>show('화면 오류: '+message(event.error||event.message)));
window.addEventListener('unhandledrejection',event=>show('실행 오류: '+message(event.reason)));
show('화면을 시작하는 중…');
try{
 await import('./popup.js');
 show('화면 준비 완료 · 실행 서비스 확인 중…');
 let timer;
 try{
  const result=await Promise.race([chrome.runtime.sendMessage({type:'APP_HEALTH'}),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('5초 동안 응답 없음')),5000);})]);
  if(!result?.ok)throw new Error('서비스가 최신 진단 요청에 응답하지 않습니다. 확장 관리에서 다시 로드하세요.');
  health.remove();
 }catch(e){show('실행 서비스 연결 실패: '+message(e));}finally{clearTimeout(timer);}
}catch(e){show('기능 초기화 실패: '+message(e));}
chrome.storage.onChanged.addListener((changes,area)=>{
 if(area==='session'&&changes.quickOpen?.newValue){const state=changes.quickOpen.newValue;show((state.ok===false?'중단 · ':'실행 · ')+state.text);}
});
