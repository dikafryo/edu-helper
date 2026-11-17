import './lib/start-lock.js';
import { proofreadNotice } from './lib/proofread.js';
import { prepareNotice,currentNotice } from './lib/notice-rich-ui.js';
const statusEl=document.getElementById('status');
const targetEl=document.getElementById('target');
const pinBtn=document.getElementById('pinBtn');
function setStatus(m) {
  const t = m || '';
  statusEl.textContent = t;
  if (t) statusEl.hidden = false; else statusEl.hidden = true;
}
function setTarget(title, url) {
  const t = String(title || '').trim() || '(제목 없음)';
  targetEl.textContent = t;
  targetEl.title = (url ? url + '\n' : '') + t;
}

async function refreshTarget() {
  try {
    const r = await chrome.runtime.sendMessage({ type: 'DOCK_GET_TARGET' });
    if (r && r.ok && r.tabId) {
      setTarget(r.title || '', r.url || '');
      return r;
    }
    setTarget('대상 창을 클릭하세요', '');
    return null;
  } catch (_) {
    setTarget('대상 없음', '');
    return null;
  }
}

function setPinUi(on) {
  pinBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
  pinBtn.title = on
    ? '위치 고정 ON · 업무 창 옆에 배치 (포커스 유지)'
    : '위치 고정 · 업무 창 옆에 배치';
}

async function refreshPin() {
  try {
    const r = await chrome.runtime.sendMessage({ type: 'DOCK_PIN_GET' });
    setPinUi(!!(r && r.pinned));
  } catch (_) { setPinUi(false); }
}

pinBtn.addEventListener('click', async () => {
  const next = pinBtn.getAttribute('aria-pressed') !== 'true';
  try {
    const r = await chrome.runtime.sendMessage({ type: 'DOCK_PIN_SET', pinned: next });
    if (!r?.ok) throw new Error(r?.error || '핀고정 상태를 저장하지 못했습니다.');
    setPinUi(!!(r && r.pinned));
    setStatus(r && r.pinned
      ? '위치 고정 ON · 주소창과 업무 입력 포커스를 유지합니다'
      : '핀 OFF');
  } catch (e) {
    setStatus(String((e && e.message) || e));
  }
});

document.getElementById('actions').addEventListener('click',async event=>{
 const button=event.target.closest('button[data-act]');if(!button||button.disabled)return;
 button.disabled=true;
 try{
  const gate=await chrome.runtime.sendMessage({type:'VAULT_STATUS'});
  if(gate?.pinLockEnabled&&!gate.unlocked)throw new Error('PIN 잠금을 먼저 해제하세요.');
  const action=button.dataset.act;
  if(action==='noticeDraft'){await prepareNotice();return;}
  const page=currentNotice();
  if(action==='proofread'){
   const result=proofreadNotice(page.body);if(!result.ok)throw new Error('본문을 입력한 뒤 오타확인을 누르세요.');
   setStatus(result.text);return;
  }
  if(action==='travelApplication'){
   const result=await chrome.runtime.sendMessage({type:'OPEN_WORK_PAGE',page:'trip'});
   if(!result?.ok)throw new Error(result?.error||'출장 신청 화면을 열지 못했습니다.');setStatus(result.message);return;
  }
  if(action==='todoAdd'){
   if(!page.title)throw new Error('캘린더에 추가할 제목을 입력하세요.');
   const result=await chrome.runtime.sendMessage({type:'GCAL_OPEN',title:page.title,details:page.body});
   if(!result?.ok)throw new Error(result?.error||'Google 캘린더를 열지 못했습니다.');
   setStatus('Google 캘린더 일정 작성 화면을 열었습니다. 날짜·시간을 확인하고 저장하세요.');
  }
 }catch(e){setStatus(e.message);}finally{button.disabled=false;}
});
async function syncPos() {
  try {
    const me = await chrome.windows.getCurrent();
    await chrome.runtime.sendMessage({ type: 'DOCK_REPOSITION', dockWinId: me && me.id });
    await refreshTarget();
  } catch (_) {}
}

async function hello() {
  try {
    const me = await chrome.windows.getCurrent();
    const r = await chrome.runtime.sendMessage({ type: 'DOCK_HELLO', dockWinId: me && me.id });
    if (r && r.close) {
      try { window.close(); } catch (_) {}
      return;
    }
    if (r && r.title) setTarget(r.title, '');
    else await refreshTarget();
  } catch (_) {
    await refreshTarget();
  }
  await refreshPin();
}
void hello();

setInterval(syncPos, 1500);

let radialBusy=false;
async function consumeRadialAction() {
 if(radialBusy)return;radialBusy=true;
 try {
  const {pendingRadialAction:pending}=await chrome.storage.session.get('pendingRadialAction');
  if(!pending)return;
  await chrome.storage.session.remove('pendingRadialAction');
  if(Date.now()-pending.nonce>30000)return;
  const gate=await chrome.runtime.sendMessage({type:'VAULT_STATUS'});
  if(gate?.pinLockEnabled&&!gate.unlocked)return;
  if(pending.action==='travel')document.querySelector('[data-act="travelApplication"]').click();
  if(pending.action==='notice')document.querySelector('[data-act="noticeDraft"]').click();
 }finally{radialBusy=false;}
}
chrome.storage.onChanged.addListener((changes,area)=>{
 if(area==='session' && changes.pendingRadialAction?.newValue)void consumeRadialAction();
});
void consumeRadialAction();
