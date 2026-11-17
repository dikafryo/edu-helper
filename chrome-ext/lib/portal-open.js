// 업무포털(eduptl) 인증서 창은 페이지 안 레이어다. 비밀번호는 그 칸에만 한 번 넣는다.
const PORTAL_HOME = 'https://pen.eduptl.kr/';
const CERT_GAP_MS = 20000;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function isEduptl(url) {
  try {
    const host = new URL(url).hostname;
    return host === 'eduptl.kr' || host.endsWith('.eduptl.kr');
  } catch (_) {
    return false;
  }
}

function isNeisMain(url) {
  try {
    const u = new URL(url);
    return u.hostname.endsWith('.neis.go.kr') && u.pathname.startsWith('/jsp/main.jsp');
  } catch (_) {
    return false;
  }
}

export function chooseCertIndex(users, hint, opened, selectedIndex) {
  if (!users.length) return -1;
  if (users.length === 1) return 0;
  const hinted = hint ? users.indexOf(hint) : -1;
  if (hinted >= 0) return hinted;
  if (!opened && selectedIndex >= 0) return selectedIndex;
  return -1;
}

export function readPortalScreen() {
  const shown = (el) => !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects?.().length);
  const menu = [...document.querySelectorAll('a.menuBtn')].some(shown);
  if (menu) return 'main';
  const label = (el) => (el.innerText || el.value || el.getAttribute?.('aria-label') || '').replace(/\s+/g, '');
  const byId = document.querySelector('#btnLgn');
  if (shown(byId)) return 'login';
  const hits = [...document.querySelectorAll('a,button,[role="button"]')].filter((el) => shown(el) && label(el).includes('교육행정전자서명인증서로그인'));
  const outer = hits.filter((el) => !hits.some((other) => other !== el && other.contains?.(el)));
  return outer.length === 1 ? 'login' : null;
}

export async function prepareCertDialog(hint) {
  const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const shown = (el) => !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects?.().length);
  const dialog = () => document.querySelector('#kc_dialog_default');
  const loginButton = () => {
    const label = (el) => (el.innerText || el.value || el.getAttribute?.('aria-label') || '').replace(/\s+/g, '');
    const byId = document.querySelector('#btnLgn');
    if (shown(byId)) return byId;
    const hits = [...document.querySelectorAll('a,button,[role="button"]')].filter((el) => shown(el) && label(el).includes('교육행정전자서명인증서로그인'));
    const outer = hits.filter((el) => !hits.some((other) => other !== el && other.contains?.(el)));
    const preferred = outer.filter((el) => /^(A|BUTTON)$/i.test(el.tagName || ''));
    const pool = preferred.length ? preferred : outer;
    return pool.length === 1 ? pool[0] : null;
  };
  const dialogShown = () => {
    if (shown(dialog())) return true;
    const pwd = document.querySelector('#kc_content_default input[name=certPassword]');
    if (shown(pwd)) return true;
    return shown(dialog()?.closest?.('[role="dialog"]'));
  };
  let opened = false;
  if (!dialogShown()) {
    const btn = loginButton();
    if (!shown(btn)) return { ok: false, error: '교육행정 전자서명 인증서 로그인 버튼이 보이지 않습니다.' };
    if(btn.disabled || btn.getAttribute?.('aria-disabled')==='true')return {ok:false,error:'인증서 로그인 버튼이 아직 준비되지 않았습니다.'};
    for(let attempt=0;attempt<3 && !dialogShown();attempt++){
      btn.click();
      opened=true;
      const deadline=Date.now()+4000;
      while(!dialogShown() && Date.now()<deadline)await pause(150);
    }
    if(!dialogShown())return {ok:false,error:'인증서 창 열기를 3회 시도했지만 창이 나타나지 않았습니다. 인증서 프로그램 상태를 확인하세요.'};
  }
  const end=Date.now()+15000;
  let rows = [];
  while (Date.now() < end) {
    rows = [...document.querySelectorAll('#kc_cert_list table tbody tr')].filter(shown);
    if (dialogShown() && rows.length) break;
    rows = [];
    await pause(150);
  }
  if (!rows.length) return { ok: false, error: '로그인 버튼에 포커스를 주고 실행했지만 웹 인증서 목록이 확인되지 않았습니다. Tab → Space로 직접 연 뒤 교직원 업무도우미 업무포털을 다시 누르면 열린 인증서 창에서 이어갑니다.' };
  const users = rows.map((row) => (row.cells?.[1]?.innerText || '').trim());
  const selected = rows.findIndex((row) => row.classList.contains('kc-tableview-selected-row'));
  let index = -1;
  if (users.length === 1) index = 0;
  else if (hint && users.indexOf(hint) >= 0) index = users.indexOf(hint);
  else if (!opened && selected >= 0) index = selected;
  if (index < 0) return { ok: false, error: '인증서가 여러 개입니다. 창에서 하나를 고른 뒤 다시 누르세요.', count: rows.length };
  if (!rows[index].classList.contains('kc-tableview-selected-row')) {
    (rows[index].cells?.[0] || rows[index]).click();
    await pause(200);
  }
  return { ok: true, user: users[index], multiple: rows.length > 1 };
}

export function inspectCertFrame(){
 const dialog=document.querySelector('#kc_dialog_default');
 const input=document.querySelector('#kc_dialog_default input[name=certPassword]')||document.querySelector('#kc_content_default input[name=certPassword]');
 const shown=el=>!!el && !!(el.offsetWidth||el.offsetHeight||el.getClientRects?.().length);
 return {found:shown(dialog)||shown(input)||shown(dialog?.closest?.('[role="dialog"]')),hasInput:!!input};
}

export function submitCertPassword(password) {
  const input = document.querySelector('#kc_dialog_default input[name=certPassword]');
  const btn = document.querySelector('#kc_dialog_default button.kc-btn-blue');
  if (!input || !btn) return {ok:false,error:'인증서 비밀번호 입력칸 또는 확인 버튼을 찾지 못했습니다.'};
  if (typeof password !== 'string' || !password) return {ok:false,error:'저장된 인증서 비밀번호가 없습니다. 설정 → 인증서 비밀번호에서 저장하세요.'};
  input.focus();
  const proto = typeof HTMLInputElement === 'function' ? HTMLInputElement.prototype : null;
  const setter = proto ? Object.getOwnPropertyDescriptor(proto, 'value')?.set : null;
  if (setter) setter.call(input, password);
  else input.value = password;
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
  btn.click();
  return true;
}

export function readPortalLoginError(){
  const shown=el=>!!el.getClientRects().length;
  const alerts=[...document.querySelectorAll('[role="alert"],[role="alertdialog"]')].filter(shown);
  const text=alerts.map(el=>el.innerText||'').join(' ');
  if(/비밀번호|암호/.test(text)&&/틀|오류|실패|일치하지/.test(text))return '인증서 비밀번호 오류가 표시되었습니다. 설정의 인증서 비밀번호를 확인하세요. 자동 재입력은 하지 않았습니다.';
  if(/인증서/.test(text)&&/만료|폐기/.test(text))return '인증서 만료·폐기 안내가 표시되었습니다. 인증서 상태를 확인하세요.';
  return '';
}

export function menuTarget(label) {
  const shown = (el) => !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects?.().length);
  const link = [...document.querySelectorAll('a.menuBtn')].find((el) => shown(el) && (el.innerText || '').trim() === label);
  if (!link) return { found: false };
  let url = '';
  try {
    const fromId = new URL(link.id);
    if (fromId.protocol === 'https:') url = fromId.href;
  } catch (_) { /* id가 주소가 아님 */ }
  if (!url) {
    try {
      const fromHref = new URL(link.href, location.href);
      if (fromHref.protocol === 'https:' && fromHref.hostname !== location.hostname) url = fromHref.href;
    } catch (_) { /* 상대 주소 무시 */ }
  }
  if (!url) link.click();
  return { found: true, url };
}

async function note(text, ok = true) {
  await chrome.storage.session.set({ quickOpen: { text, ok, at: Date.now() } });
}

async function waitFor(check, timeoutMs) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const value = await check();
    if (value) return value;
    await sleep(500);
  }
  return null;
}

async function screenOf(tabId) {
  const frames = await chrome.scripting.executeScript({ target: { tabId, allFrames: true }, func: readPortalScreen }).catch(() => []);
  const states = frames.map((frame) => frame.result);
  if (states.includes('main')) return 'main';
  if (states.includes('login')) return 'login';
  return null;
}

async function findPortalMain() {
  const tabs = await chrome.tabs.query({ url: 'https://*.eduptl.kr/*' });
  tabs.sort((a, b) => Number(b.active) - Number(a.active));
  for (const tab of tabs) {
    if (await screenOf(tab.id) === 'main') return tab;
  }
  return null;
}

async function findReadyNeis() {
  const tabs = (await chrome.tabs.query({})).filter((tab) => isNeisMain(tab.url) && tab.status === 'complete');
  for (const tab of tabs) {
    const [frame] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      world: 'MAIN',
      func: () => !!window.cpr?.core?.Platform?.INSTANCE && !!document.querySelector('a.cl-sidenavigation-item')
    }).catch(() => []);
    if (frame?.result) return tab;
  }
  return null;
}

async function focusTab(tab) {
  await chrome.tabs.update(tab.id, { active: true });
  await chrome.windows.update(tab.windowId, { focused: true });
}

function runInPage(tabId, func, args) {
  return chrome.scripting.executeScript({ target: { tabId }, func, args });
}

async function loginWithCert(tabId, password) {
  const hasPassword = typeof password === 'string' && !!password;
  if (hasPassword) {
    const { certPendingAt = 0 } = await chrome.storage.session.get('certPendingAt');
    if (Date.now() - Number(certPendingAt) < CERT_GAP_MS) {
      return { ok: false, error: '인증서 비밀번호는 연속으로 넣지 않습니다. 20초 뒤 창을 확인하고 다시 누르세요.' };
    }
  }
  const { certHint = '' } = await chrome.storage.local.get('certHint');
  await note(hasPassword ? '인증서 로그인 버튼을 누르고 비밀번호를 입력합니다.' : '인증서 로그인 창을 여는 중…');
  const [prep] = await runInPage(tabId, prepareCertDialog, [certHint]).catch(() => []);
  if (!prep?.result?.ok) return prep?.result || { ok: false, error: '웹 인증서 창을 확인하지 못했습니다. 별도 프로그램 창인지 확인해주세요.' };
  if (!hasPassword) return { ok: false, error: '인증서 창을 열었습니다. 설정 → 인증서 비밀번호에서 저장하거나 열린 창에 직접 한 번만 입력하세요.' };
  await note('선택된 인증서로 로그인 요청 중…');
  await chrome.storage.session.set({ certPendingAt: Date.now() });
  const [sent] = await runInPage(tabId, submitCertPassword, [password]).catch(() => []);
  if (sent?.result !== true) {
    await chrome.storage.session.set({ certPendingAt: 0 });
    return { ok: false, error: sent?.result?.error || '인증서 비밀번호 입력에 실패했습니다. 열린 인증서 창을 확인하세요.' };
  }
  if (prep.result.multiple && prep.result.user) await chrome.storage.local.set({ certHint: prep.result.user });
  return { ok: true };
}

async function ensurePortal(password) {
  if (await findPortalMain()) return { ok: true };
  const tabs = await chrome.tabs.query({ url: 'https://*.eduptl.kr/*' });
  let tab = tabs.find((item) => item.active) || tabs[0];
  if (tab) await focusTab(tab);
  else {
    await note('업무포털을 여는 중…');
    tab = await chrome.tabs.create({ url: PORTAL_HOME, active: true });
  }
  await note('업무포털 화면을 기다리는 중…');
  const state = await waitFor(async () => {
    const current = await chrome.tabs.get(tab.id).catch(() => null);
    if (!current) return 'gone';
    if (current.status !== 'complete' || !isEduptl(current.url)) return null;
    return screenOf(tab.id);
  }, 30000);
  if (state === 'main') return { ok: true };
  if (state !== 'login') return { ok: false, error: state === 'gone' ? '업무포털 탭이 닫혔습니다.' : '업무포털 로그인 화면을 확인하지 못했습니다.' };
  await note('인증서로 로그인하는 중…');
  const sent = await loginWithCert(tab.id, password);
  if (!sent.ok) return sent;
  await note('인증서 입력 완료 · 업무포털 응답 확인 중… (최대 25초)');
  const main = await waitFor(async()=>{
    if(await screenOf(tab.id)==='main')return {id:tab.id};
    const [error]=await chrome.scripting.executeScript({target:{tabId:tab.id},func:readPortalLoginError}).catch(()=>[]);
    if(error?.result)return {error:error.result};
    return findPortalMain();
  }, 25000);
  if(main?.error)return {ok:false,error:main.error};
  if (!main) return { ok: false, error: '로그인 완료가 확인되지 않았습니다. 비밀번호가 틀리면 다시 누르지 말고 인증서 창을 확인하세요.' };
  await chrome.storage.session.set({ certPendingAt: 0 });
  return { ok: true };
}

async function openLabeledMenu(labels) {
  const main = await findPortalMain();
  if (!main) return { ok: false, error: '로그인된 업무포털 화면이 없습니다.' };
  for (const label of labels) {
    const [frame] = await chrome.scripting.executeScript({
      target: { tabId: main.id },
      func: menuTarget,
      args: [label]
    }).catch(() => []);
    const result = frame?.result;
    if (!result?.found) continue;
    if (result.url) await chrome.tabs.create({ url: result.url, windowId: main.windowId, index: main.index + 1, active: true });
    return { ok: true };
  }
  return { ok: false, error: '업무포털 상단 메뉴를 찾지 못했습니다.' };
}

let opening = false;

export async function startQuickOpen(target, password) {
  if (opening) return { ok: false, error: '바로 열기가 진행 중입니다.' };
  if (!['portal','edufine','neis'].includes(target)) return {ok:false,error:'지원하지 않는 바로가기입니다.'};
  opening = true;
  try {
    if (target === 'neis') {
      const ready = await findReadyNeis();
      if (ready) {
        await focusTab(ready);
        await note('이미 열린 나이스로 이동했습니다.');
        return { ok: true, message: '이미 열린 나이스로 이동했습니다.' };
      }
    }
    const login = await ensurePortal(password);
    if (!login.ok) {
      await note(login.error, false);
      return login;
    }
    if (target === 'portal') {
      const main = await findPortalMain();
      if (main) await focusTab(main);
      await note('업무포털에 로그인되어 있습니다.');
      return { ok: true, message: '업무포털에 로그인되어 있습니다.' };
    }
    const labels = target === 'edufine' ? ['K-에듀파인', '에듀파인'] : ['나이스'];
    await note(labels[0] + '을 여는 중…');
    const opened = await openLabeledMenu(labels);
    if (!opened.ok) {
      await note(opened.error, false);
      return opened;
    }
    if (target === 'neis') {
      await note('나이스 화면을 기다리는 중…');
      const ready = await waitFor(findReadyNeis, 60000);
      if (!ready) {
        const error = '나이스 화면이 준비되지 않았습니다. 열린 창을 확인하세요.';
        await note(error, false);
        return { ok: false, error };
      }
      await focusTab(ready);
    }
    const message = target === 'edufine' ? 'K-에듀파인을 열었습니다.' : '나이스를 열었습니다.';
    await note(message);
    return { ok: true, message };
  } catch (error) {
    const message = '바로 열기 실패: ' + (error?.message || String(error));
    await note(message, false);
    return {ok:false,error:message};
  } finally {
    opening = false;
  }
}

export async function quickOpenStatus() {
  const { quickOpen = null } = await chrome.storage.session.get('quickOpen');
  return quickOpen;
}
