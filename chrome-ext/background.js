import {openOfficialMail} from './lib/official-mail.js';
import { openWorkPage } from './lib/work-page.js';
import { readDocumentContext, markTargetFrame, parseIssuedReference } from './lib/document-context.js';
import { summarizeGongmun, rankTaskCards, getPromptAvailability, getSummarizerAvailability, polishGongmun } from './lib/ondevice-ai.js';
import {
  newSchoolNoticeDraft, formatAttachEnding, hwpPasteChecklist, annotateOutdentLines,
  grokPrepPacket, unmaskPersonalInfo, tripDraftFromNotice, dueDateFromText
} from './lib/notice.js';
import {
  addTodo, removeTodo, setTodoDone, registerScheduleFromTodo, listWorkItems,
  markScheduleGoogleSaved, loadTodos, loadSchedules
} from './lib/todos.js';
import { newGCalTemplateUrl } from './lib/gcal.js';
import {
  encryptPayload, decryptPayload, makePinVerify, verifyPinHash, normalizePin,
  MAX_FAIL, UNLOCK_MS_DEFAULT
} from './lib/vault.js';

const KEEP_ALARM = 'pen-keepalive'; // legacy name — cleared, never recreated
import { buildDutyData } from './lib/duty.js';
import { workflowStep } from './lib/workflow.js';
import { prepareRoute, startNeisRoute } from './lib/neis-route.js';
import { startQuickOpen, quickOpenStatus } from './lib/portal-open.js';
import { DEFAULT_EXTERNAL_SERVICES } from './lib/external-services.js';

const DEFAULTS = {
  theme: 'sky',
  keepAliveEnabled: false, // 에듀파인 기본 OFF: no pings/fetch/iframes
  taskCards: [],
  travelForm: {},
  dutyForm: {},
  dutyPresets: [],
  pinLockEnabled: false,
  pinVerify: null,
  vaultBlob: null,
  pinFailCount: 0,
  penUnlockedUntil: 0,
  unlockMs: 600000,
  todos: [],
  schedules: [],
  gcalSaved: {},
  lastMaskPairs: [],
  pendingGcal: null,
  externalServices: DEFAULT_EXTERNAL_SERVICES
};


async function seedDutyPresetsFromPackage() {
  try {
    const cur = await chrome.storage.local.get(['dutyPresets', 'dutyPresetsSeeded']);
    if (cur.dutyPresetsSeeded) return;
    if (Array.isArray(cur.dutyPresets) && cur.dutyPresets.length) {
      await chrome.storage.local.set({ dutyPresetsSeeded: true });
      return;
    }
    const res = await fetch(chrome.runtime.getURL('data/duty_presets.json'));
    if (!res.ok) return;
    const presets = await res.json();
    if (Array.isArray(presets) && presets.length) {
      await chrome.storage.local.set({ dutyPresets: presets, dutyPresetsSeeded: true });
    }
  } catch (_) { /* ignore */ }
}

async function seedTaskCardsFromPackage() {
  // SEED_TASK_CARDS_FROM_PACKAGE — one-time from bundled data/task_cards.json
  try {
    const cur = await chrome.storage.local.get(['taskCards', 'taskCardsSeeded']);
    if (cur.taskCardsSeeded) return;
    if (Array.isArray(cur.taskCards) && cur.taskCards.length) {
      await chrome.storage.local.set({ taskCardsSeeded: true });
      return;
    }
    const res = await fetch(chrome.runtime.getURL('data/task_cards.json'));
    if (!res.ok) return;
    const cards = await res.json();
    if (Array.isArray(cards) && cards.length) {
      await chrome.storage.local.set({ taskCards: cards, taskCardsSeeded: true });
    }
  } catch (_) { /* ignore */ }
}


async function clearLegacyKeepAlive() {
  try { await chrome.alarms.clear(KEEP_ALARM); } catch (_) {}
}

/** In-memory only while unlocked. Cleared on lock / idle / wipe / SW sleep. */
let memSession = null; // Restored only from trusted browser-session memory.
let pinSessionWrite=Promise.resolve();
let pinSessionEpoch=0;
async function restorePinSession() {
 const epoch=pinSessionEpoch;
 await pinSessionWrite;
 if(memSession)return;
 try {
  const {penPinSession:saved}=await chrome.storage.session.get('penPinSession');
  const st=await chrome.storage.local.get(['penUnlockedUntil','pinLockEnabled']);
  if(epoch===pinSessionEpoch && saved && st.pinLockEnabled && saved.until===st.penUnlockedUntil && saved.until>Date.now())memSession=saved.session;
 }catch(_){}
}

async function syncPinBadge() {
  try {
    await restorePinSession();
    const st = await chrome.storage.local.get(['pinLockEnabled', 'penUnlockedUntil']);
    const on = !!st.pinLockEnabled && !!memSession && Number(st.penUnlockedUntil) > Date.now();
    await chrome.action.setBadgeBackgroundColor({ color: '#16803c' });
    await chrome.action.setBadgeText({ text: on ? 'ON' : '' });
    const title = !st.pinLockEnabled ? '교직원 업무도우미' : (on ? '교직원 업무도우미 · PIN 잠금 해제됨' : '교직원 업무도우미 · PIN 잠김');
    await chrome.action.setTitle({ title });
  } catch (_) { /* Badge errors must not affect authentication. */ }
}

function clearMemSession() {
  memSession = null;pinSessionEpoch++;
  pinSessionWrite=pinSessionWrite.then(()=>chrome.storage.session.remove('penPinSession')).catch(()=>{});
  void syncPinBadge();
}

async function markUnlocked(ms) {
  const duration=Number(ms)>0 ? Math.min(Number(ms),86400000) : UNLOCK_MS_DEFAULT;
  const until = Date.now() + duration;
  await chrome.storage.local.set({ penUnlockedUntil: until, pinFailCount: 0 });
  const savedSession=memSession;
  const write=pinSessionWrite.then(()=>chrome.storage.session.set({penPinSession:{until,session:savedSession}}));
  pinSessionWrite=write.catch(()=>{});
  try { await write; } catch (_) { await lockNow(); throw new Error('잠금 해제 상태 저장 실패 · 확장을 새로고침한 뒤 다시 시도하세요.'); }
  await pinSessionWrite;
  await chrome.alarms.create('pen-pin-expiry', { when: until });
  await syncPinBadge();
  return until;
}

async function lockNow() {
  clearMemSession();
  await chrome.storage.local.set({ penUnlockedUntil: 0 });
  return { ok: true, locked: true };
}

async function wipeVaultStorage() {
  clearMemSession();
  await chrome.storage.local.set({
    vaultBlob: null,
    pinFailCount: 0,
    penUnlockedUntil: 0
  });
  return { ok: true, wiped: true };
}

async function pinAttemptBlocked() {
  const st = await chrome.storage.local.get(['pinBlockedUntil']);
  if (Number(st.pinBlockedUntil || 0) > Date.now()) return 'PIN 입력이 잠시 제한되었습니다. 5분 뒤 다시 시도하세요.';
  return '';
}

async function recordPinFailure() {
  const st = await chrome.storage.local.get(['pinFailCount']);
  const fails = Number(st.pinFailCount || 0) + 1;
  if (fails >= MAX_FAIL) {
    await chrome.storage.local.set({ pinFailCount: 0, pinBlockedUntil: Date.now() + 300000, penUnlockedUntil: 0 });
    clearMemSession();
    return 'PIN 5회 오류 · 5분 동안 입력 제한. 기존 PIN과 금고는 유지됩니다.';
  }
  await chrome.storage.local.set({ pinFailCount: fails });
  return 'PIN 오류 (' + fails + '/' + MAX_FAIL + ')';
}

function certPasswordFrom(session) {
  if (typeof session?.certPassword === 'string' && session.certPassword) return session.certPassword;
  if (typeof session?.secrets?.certPassword === 'string' && session.secrets.certPassword) return session.secrets.certPassword;
  return '';
}

async function savedCertPassword() {
  // PIN 금고를 쓰지 않아도 설정에서 저장한 인증서 비밀번호를 사용한다.
  const fromSession = certPasswordFrom(memSession);
  if (fromSession) return fromSession;
  try {
    const { certPassword = '' } = await chrome.storage.local.get('certPassword');
    return typeof certPassword === 'string' ? certPassword : '';
  } catch (_) {
    return '';
  }
}

/* ===== 외부 서비스 자동 로그인 ===== */

function fillExternalPassword(args) {
  const visible = (el) => !!el && el.getClientRects().length > 0 && !el.disabled;
  const label = (el) => (el.innerText || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, '').toLowerCase();
  const inputs = [...document.querySelectorAll('input')].filter(visible);
  const password = inputs.find((el) => (el.type || '').toLowerCase() === 'password');
  if (!password) return { ok: false, error: '비밀번호 입력칸을 찾지 못했습니다. 직접 로그인하세요.' };
  const idInput = inputs.find((el) => el !== password && ['text', 'email', 'tel', 'number'].includes((el.type || 'text').toLowerCase()));
  if (!idInput) return { ok: false, error: '아이디 입력칸을 찾지 못했습니다. 직접 로그인하세요.' };
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
  const set = (el, value) => {
    if (setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };
  set(idInput, String(args.userId || ''));
  set(password, String(args.password || ''));
  const controls = [...document.querySelectorAll('button,input[type=submit],a')].filter(visible);
  const submit = controls.find((el) => ['로그인', '로그인하기', 'signin', 'login'].includes(label(el)));
  if (!submit) return { ok: false, error: '로그인 버튼을 찾지 못했습니다. 직접 눌러 주세요.' };
  submit.click();
  return { ok: true, message: '아이디·비밀번호를 입력하고 로그인을 눌렀습니다.' };
}

function clickExternalCertLogin() {
  const visible = (el) => !!el && el.getClientRects().length > 0 && !el.disabled;
  const label = (el) => (el.innerText || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, '').toLowerCase();
  const controls = [...document.querySelectorAll('a,button,[role="button"],input[type="button"],input[type="submit"]')].filter(visible);
  if (controls.some((el) => label(el) === '로그아웃' || label(el) === 'logout')) {
    return { ok: true, already: true, message: '이미 로그인되어 있습니다.' };
  }
  const target = controls.find((el) => label(el).includes('인증서') && label(el).includes('로그인'));
  if (!target) return { ok: false, error: '인증서 로그인 버튼을 찾지 못했습니다. 직접 로그인하세요.' };
  target.click();
  return { ok: true };
}

function fillExternalCertPassword(password) {
  const input = document.querySelector('#kc_dialog_default input[name=certPassword]') || document.querySelector('#kc_content_default input[name=certPassword]');
  const button = document.querySelector('#kc_dialog_default button.kc-btn-blue') || document.querySelector('#kc_content_default button.kc-btn-blue');
  if (!input || !button) return { ok: false, error: '인증서 비밀번호 창을 찾지 못했습니다.' };
  if (!password) return { ok: false, error: '저장된 인증서 비밀번호가 없습니다.' };
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
  if (setter) setter.call(input, String(password)); else input.value = String(password);
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
  button.click();
  return { ok: true };
}

async function focusOrOpenExternalService(domain) {
  const origin = new URL(domain).origin;
  const tabs = await chrome.tabs.query({});
  const tab = tabs.find((item) => {
    try { return !!item.url && new URL(item.url).origin === origin; } catch (_) { return false; }
  });
  if (tab) {
    await chrome.tabs.update(tab.id, { active: true });
    try { await chrome.windows.update(tab.windowId, { focused: true }); } catch (_) {}
    return tab;
  }
  return chrome.tabs.create({ url: domain, active: true });
}

async function waitForTabComplete(tabId) {
  const end = Date.now() + 15000;
  while (Date.now() < end) {
    try {
      const tab = await chrome.tabs.get(tabId);
      if (tab?.status === 'complete') return tab;
    } catch (_) {
      return null;
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  try { return await chrome.tabs.get(tabId); } catch (_) { return null; }
}

async function runInjected(tabId, func, args) {
  try {
    const frames = await chrome.scripting.executeScript({ target: { tabId, allFrames: true }, func, args });
    const results = frames.map((frame) => frame.result).filter(Boolean);
    return results.find((result) => result.ok) || results[0] || { ok: false, error: '응답이 없습니다.' };
  } catch (_) {
    return { ok: false, error: '이 사이트에 자동 로그인 권한이 없습니다. 설정 → 외부 서비스에서 다시 저장해 권한을 허용하세요.' };
  }
}

async function openExternalService(serviceId) {
  const stored = await chrome.storage.local.get('externalServices');
  const list = Array.isArray(stored.externalServices) && stored.externalServices.length
    ? stored.externalServices
    : DEFAULT_EXTERNAL_SERVICES;
  const service = list.find((item) => item && item.id === serviceId);
  if (!service) return { ok: false, error: '저장된 외부 서비스를 찾지 못했습니다.' };
  let serviceUrl;
  try { serviceUrl = new URL(service.domain); } catch (_) { return { ok: false, error: '서비스 도메인을 확인하세요.' }; }
  if (serviceUrl.protocol !== 'http:' && serviceUrl.protocol !== 'https:') {
    return { ok: false, error: 'http:// 또는 https:// 주소만 열 수 있습니다.' };
  }
  const insecure = serviceUrl.protocol === 'http:';
  const warning = insecure
    ? '이 서비스는 SSL 보안이 지원되지 않습니다. 아이디·비밀번호가 암호화되지 않은 채 전송될 수 있습니다.'
    : '';
  const done = (result) => (warning ? { ...result, warning } : result);
  if (serviceUrl.protocol === 'https:' && (service.id === 'official-mail' || serviceUrl.hostname === 'mail.korea.kr')) {
    return done(await openOfficialMail(await savedCertPassword()));
  }
  let tab;
  try { tab = await focusOrOpenExternalService(serviceUrl.href); }
  catch (_) { return done({ ok: false, error: '서비스 주소를 열지 못했습니다. 도메인을 확인하세요.' }); }
  if (!tab?.id) return done({ ok: false, error: '서비스 탭을 열지 못했습니다.' });
  await waitForTabComplete(tab.id);

  if (service.method === 'certificate') {
    const password = await savedCertPassword();
    const clicked = await runInjected(tab.id, clickExternalCertLogin, []);
    if (clicked?.already) return done({ ok: true, message: clicked.message || '이미 로그인되어 있습니다.' });
    if (!clicked?.ok) return done({ ok: true, needsUser: true, message: clicked?.error || '인증서 로그인을 직접 진행하세요.' });
    if (!password) return done({ ok: true, needsUser: true, message: '인증서 로그인 창을 열었습니다. 비밀번호를 직접 입력하세요.' });
    for (let i = 0; i < 20; i++) {
      await new Promise((resolve) => setTimeout(resolve, 300));
      const filled = await runInjected(tab.id, fillExternalCertPassword, [password]);
      if (filled?.ok) return done({ ok: true, message: '인증서 로그인을 진행했습니다.' });
    }
    return done({ ok: true, needsUser: true, message: '인증서 로그인 창을 열었습니다. 직접 마무리해 주세요.' });
  }

  if (!service.userId || !service.password) {
    return done({ ok: true, needsUser: true, message: '저장된 아이디·비밀번호가 없습니다. 설정에서 등록하세요.' });
  }
  const filled = await runInjected(tab.id, fillExternalPassword, [{
    userId: String(service.userId),
    password: String(service.password)
  }]);
  if (!filled?.ok) return done({ ok: true, needsUser: true, message: filled?.error || '자동 로그인하지 못했습니다. 직접 로그인하세요.' });
  return done({ ok: true, message: filled.message || '아이디·비밀번호를 입력했습니다.' });
}

function rememberVault(data) {
  memSession.secrets = data && typeof data === 'object' ? data : null;
  if (data && data.portal) memSession.portal = data.portal;
  if (data && typeof data.certPassword === 'string' && data.certPassword) memSession.certPassword = data.certPassword;
}

async function handlePinSet(msg) {
  // Sets/replaces PIN verify hash. Keeps the encrypted portal account and certificate password.
  const pin = normalizePin(msg.pin);
  const existing = await chrome.storage.local.get(['pinVerify', 'vaultBlob']);
  let next = {};
  if (existing.pinVerify) {
    const unlocked = await handlePinUnlock({ pin: msg.currentPin });
    if (!unlocked.ok) throw new Error(unlocked.error || '현재 PIN을 확인하세요.');
    if (existing.vaultBlob && !memSession?.secrets) throw new Error('기존 금고를 열지 못했습니다. PIN 변경을 중단합니다.');
    next = memSession?.secrets && typeof memSession.secrets === 'object' ? { ...memSession.secrets } : {};
  } else if (existing.vaultBlob) {
    throw new Error('기존 금고와 PIN 설정이 일치하지 않습니다. 금고를 확인한 뒤 다시 설정하세요.');
  }
  const verify = await makePinVerify(pin);
  const patch = { pinVerify: verify, pinLockEnabled: true, pinFailCount: 0, pinBlockedUntil: 0 };
  if (msg.portalId != null || msg.portalPassword != null) {
    const id = String(msg.portalId == null ? '' : msg.portalId);
    const password = String(msg.portalPassword == null ? '' : msg.portalPassword);
    if (!id || !password) throw new Error('아이디와 비밀번호를 모두 입력하세요');
    next.portal = { id, password };
  }
  if (typeof msg.certPassword === 'string' && msg.certPassword) next.certPassword = msg.certPassword;
  if (next.portal || next.certPassword) patch.vaultBlob = await encryptPayload(pin, next);
  await chrome.storage.local.set(patch);
  memSession = { pinVerifiedAt: Date.now() };
  if (patch.vaultBlob) {
    const data = await decryptPayload(pin, patch.vaultBlob);
    rememberVault(data);
  }
  await markUnlocked(msg.unlockMs || UNLOCK_MS_DEFAULT);
  return { ok: true, hasVault: !!patch.vaultBlob };
}

async function handlePinUnlock(msg) {
  const blocked = await pinAttemptBlocked();
  if (blocked) return { ok: false, error: blocked };
  const st = await chrome.storage.local.get(['pinVerify', 'pinLockEnabled', 'vaultBlob', 'pinFailCount', 'unlockMs', 'pinBlockedUntil']);
  if (!st.pinLockEnabled || !st.pinVerify) {
    return { ok: false, error: 'PIN 설정을 찾지 못했습니다. 설정에서 PIN을 등록하세요.' };
  }
  let ok = false;
  try {
    ok = await verifyPinHash(msg.pin, st.pinVerify);
  } catch (_) {
    ok = false;
  }
  if (!ok) return { ok: false, error: await recordPinFailure() };
  memSession = { pinVerifiedAt: Date.now() };
  if (st.vaultBlob) {
    try {
      const data = await decryptPayload(msg.pin, st.vaultBlob);
      rememberVault(data);
    } catch (_) {
      clearMemSession();
      return { ok: false, error: '금고 복호화 실패 · 설정을 확인하세요. 금고는 보존했습니다.' };
    }
  }
  const unlockMs=[21600000,86400000].includes(Number(msg.unlockMs)) ? Number(msg.unlockMs) : st.unlockMs || UNLOCK_MS_DEFAULT;
  const unlockedUntil=await markUnlocked(unlockMs);
  return { ok: true, unlocked: true, unlockedUntil, hasPortal: !!(memSession && memSession.portal) };
}

async function handleVaultSave(msg) {
  // Re-encrypt portal creds; requires current PIN. Never logs secrets.
  const blocked = await pinAttemptBlocked();
  if (blocked) throw new Error(blocked);
  const pin = normalizePin(msg.pin);
  const st = await chrome.storage.local.get(['pinVerify', 'vaultBlob']);
  let confirmed = false;
  try { confirmed = !!(st.pinVerify && await verifyPinHash(pin, st.pinVerify)); } catch (_) { confirmed = false; }
  if (!confirmed) throw new Error(await recordPinFailure());
  const id = String(msg.portalId == null ? '' : msg.portalId);
  const password = String(msg.portalPassword == null ? '' : msg.portalPassword);
  if (!id || !password) throw new Error('아이디와 비밀번호를 모두 입력하세요');
  const next = { portal: { id, password } };
  if (memSession?.secrets?.certPassword) next.certPassword = memSession.secrets.certPassword;
  const vaultBlob = await encryptPayload(pin, next);
  await chrome.storage.local.set({ vaultBlob, pinFailCount: 0 });
  memSession = { pinVerifiedAt: Date.now() };
  rememberVault(next);
  await markUnlocked(UNLOCK_MS_DEFAULT);
  return { ok: true, saved: true };
}

function isEduptlUrl(url) {
  try {
    const host = new URL(url).hostname;
    return host === 'eduptl.kr' || host.endsWith('.eduptl.kr');
  } catch (_) {
    return false;
  }
}

async function findPortalLoginTab() {
  const focused = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  const focusedTab = focused[0];
  if (focusedTab && isEduptlUrl(focusedTab.url)) return focusedTab;
  const tabs = await chrome.tabs.query({ url: 'https://*.eduptl.kr/*' });
  if (tabs.length === 1) return tabs[0];
  if (tabs.length > 1) throw new Error('업무포털 탭이 여러 개입니다. 로그인 화면을 선택한 뒤 다시 누르세요.');
  throw new Error('업무포털(eduptl.kr) 로그인 화면을 연 뒤 다시 누르세요.');
}

async function portalLoginFrame(tabId) {
  const probes = await chrome.scripting.executeScript({
    target: { tabId, allFrames: true },
    func: () => {
      const host = location.hostname || '';
      const passwords = [...document.querySelectorAll('input')].filter((el) => {
        return (el.type || '').toLowerCase() === 'password' && el.getClientRects().length;
      }).length;
      return { portal: host === 'eduptl.kr' || host.endsWith('.eduptl.kr'), passwords };
    }
  });
  const hits = probes.filter((item) => item.result && item.result.portal && item.result.passwords === 1);
  if (hits.length !== 1) {
    throw new Error(hits.length ? '비밀번호 칸이 한 개가 아닙니다. 로그인 화면만 연 뒤 다시 누르세요.' : '업무포털 로그인 화면이 아닙니다.');
  }
  return hits[0].frameId;
}

async function portalLoginFillActiveTab() {
  const locked = await requireUnlocked();
  if (locked) return locked;
  if (!(memSession && memSession.portal && memSession.portal.id && memSession.portal.password)) {
    return { ok: false, error: '잠금 해제 후 금고에 저장된 계정 필요' };
  }
  try {
    const tab = await findPortalLoginTab();
    const frameId = await portalLoginFrame(tab.id);
    const r = await chrome.tabs.sendMessage(tab.id, {
      type: 'PORTAL_LOGIN_FILL',
      id: memSession.portal.id,
      password: memSession.portal.password
    }, { frameId });
    return r || { ok: false, error: 'no-response' };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

async function confirmCurrentPin(pin) {
  const blocked = await pinAttemptBlocked();
  if (blocked) return { ok: false, error: blocked };
  const existing = await chrome.storage.local.get(['pinVerify']);
  if (!existing.pinVerify) return { ok: true };
  let confirmed = false;
  try { confirmed = await verifyPinHash(pin, existing.pinVerify); } catch (_) { confirmed = false; }
  if (!confirmed) return { ok: false, error: await recordPinFailure() };
  return { ok: true };
}

async function handleVaultWipe(msg) {
  const confirmed = await confirmCurrentPin(msg && msg.pin);
  if (!confirmed.ok) return confirmed;
  return wipeVaultStorage();
}

async function handlePinDisable(msg) {
  const confirmed = await confirmCurrentPin(msg && msg.pin);
  if (!confirmed.ok) return confirmed;
  clearMemSession();
  await chrome.storage.local.set({
    vaultBlob: null,
    pinVerify: null,
    pinLockEnabled: false,
    pinFailCount: 0,
    pinBlockedUntil: 0,
    penUnlockedUntil: 0
  });
  return { ok: true, disabled: true };
}


chrome.runtime.onInstalled.addListener((details) => {
  void (async () => {
    const cur = await chrome.storage.local.get(null);
    await chrome.storage.local.set(Object.assign({}, DEFAULTS, cur, { keepAliveEnabled: false }));
    await clearLegacyKeepAlive();
    await seedTaskCardsFromPackage();
    await seedDutyPresetsFromPackage();
    try { await chrome.alarms.clear('pen-badge'); } catch (_) {}
    await syncPinBadge();
    if (details.reason === 'install') {
      await chrome.storage.local.set({ installedAt: new Date().toISOString() });
    }
    // rail removed: drop legacy in-page rail prefs if present
    try { await chrome.storage.local.remove('rail'); } catch (_) {}
  })();
});

chrome.runtime.onStartup.addListener(() => {
  void clearLegacyKeepAlive();
  void seedTaskCardsFromPackage();
  void seedDutyPresetsFromPackage();
});

// Restore the selected unlock period when the worker wakes.
void syncPinBadge();
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.pinLockEnabled || changes.penUnlockedUntil)) void syncPinBadge();
});

// Clear keepalive immediately when SW wakes
void clearLegacyKeepAlive();
void seedTaskCardsFromPackage();
void seedDutyPresetsFromPackage();

chrome.alarms.onAlarm.addListener((alarm) => {
  void handleAlarm(alarm);
});

async function handleAlarm(alarm) {
  if (alarm.name === 'pen-pin-expiry') {
    const st = await chrome.storage.local.get('penUnlockedUntil');
    if (Number(st.penUnlockedUntil || 0) <= Date.now()) await lockNow();
    else await syncPinBadge();
    return;
  }
  if (alarm.name === KEEP_ALARM) {
    await clearLegacyKeepAlive();
    return;
  }
  if (alarm.name === 'pen-badge') {
    try { await chrome.alarms.clear('pen-badge'); } catch (_) {}
    await syncPinBadge();
  }
}

async function requireUnlocked() {
  // PIN 잠금을 쓰지 않으면 인증 없이 모든 기능을 쓸 수 있다.
  const st = await chrome.storage.local.get(['pinLockEnabled', 'penUnlockedUntil']);
  if (!st.pinLockEnabled) return null;
  await restorePinSession();
  if (!memSession || Number(st.penUnlockedUntil) <= Date.now()) {
    return { ok: false, error: 'PIN 잠금을 먼저 해제하세요.' };
  }
  return null;
}

async function applyDutyPresetIndex(idx, overrides = {}, expectedPreset) {
  const locked = await requireUnlocked();
  if (locked) return locked;
  const { dutyPresets = [] } = await chrome.storage.local.get('dutyPresets');
  if (!Number.isInteger(idx) || idx < 0) return { ok: false, error: '복무 루틴 번호를 확인하세요.' };
  const p = dutyPresets[idx];
  if (!p) return { ok: false, error: '프리셋 없음' };
  if (expectedPreset && ['Key', 'Label', 'Reason', 'Time'].some(key => expectedPreset[key] !== p[key])) {
    return { ok: false, error: '편집 화면에서 루틴이 변경되었습니다. 팝업을 다시 열어 확인하세요.' };
  }
  let data;
  try { data = buildDutyData(p, overrides); }
  catch (error) { return { ok: false, error: error.message }; }
  await chrome.storage.local.set({ dutyForm: data });
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!(tab && tab.id)) return { ok: false, filled: 0, saved: true, error: '나이스 복무 신청 탭을 열고 다시 실행하세요.' };
  try {
    const r = await chrome.tabs.sendMessage(tab.id, { type: 'FILL_DUTY', data });
    if (!r || r.ok === false || !r.filled) {
      return { ok: false, filled: 0, saved: true, error: (r && r.error) || '루틴은 준비했지만 입력된 항목이 없습니다. 나이스 복무 신청 화면을 열고 다시 실행하세요.' };
    }
    return { ok: true, filled: r.filled, saved: true, label: data.type };
  } catch (_) {
    return { ok: false, filled: 0, saved: true, error: '루틴은 준비했지만 화면에 연결하지 못했습니다. 나이스 탭을 새로고침한 뒤 복무 신청 화면에서 다시 실행하세요.' };
  }
}


const EXTENSION_ONLY = new Set([
  'PIN_SET', 'PIN_UNLOCK', 'PIN_LOCK', 'PIN_DISABLE', 'VAULT_SAVE', 'VAULT_WIPE', 'EXTERNAL_OPEN',
  'PORTAL_LOGIN_NOW', 'NEIS_AUTO_ROUTE', 'APPLY_DUTY_PRESET', 'WORKFLOW_STEP', 'OPEN_URL',
  'QUICK_OPEN', 'QUICK_OPEN_STATUS', 'OPEN_WORK_PAGE', 'OFFICIAL_MAIL_OPEN'
]);

function fromExtensionPage(sender) {
  const own = chrome.runtime.getURL('');
  return typeof sender?.url === 'string' && sender.url.startsWith(own);
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === 'NOTICE_TITLE_SELECTED' && _sender.tab && typeof msg.title === 'string' && msg.title.length <= 500) {
    chrome.storage.session.set({lastNoticeTitle:msg.title}).then(()=>sendResponse({ok:true}));
    return true;
  }
  if (msg?.type === 'APP_HEALTH') {
    sendResponse({ok:true,version:chrome.runtime.getManifest().version});
    return false;
  }
  void (async () => {
    try {
      if (msg && EXTENSION_ONLY.has(msg.type) && !fromExtensionPage(_sender)) {
        sendResponse({ ok: false, error: '확장 화면에서만 실행할 수 있습니다.' });
        return;
      }
      if (msg?.type === 'RADIAL_ACTION') {
        const allowed=['portal','neis','edufine','travel','notice','proofread'];
        if (!_sender.tab || !isEligibleTargetTab(_sender.tab) || !allowed.includes(msg.action)) {
          sendResponse({ok:false,error:'허용된 업무 화면에서만 사용할 수 있습니다.'});return;
        }
        const locked=await requireUnlocked();
        if(locked){sendResponse(locked);return;}
        if(['portal','neis','edufine'].includes(msg.action)) {
          sendResponse(await startQuickOpen(msg.action, await savedCertPassword()));return;
        }
        if(msg.action==='proofread'){sendResponse({ok:true});return;}
        await setDockTarget(_sender.tab.id,_sender.tab.windowId);
        await chrome.storage.session.set({pendingRadialAction:{action:msg.action,tabId:_sender.tab.id,nonce:Date.now()}});
        sendResponse(await openOrFocusDock('radial-menu'));return;
      }
      // OPEN_URL: allow only explicit user clicks from popup (still no background fetch).
      // Block keepalive / main.do style session pings.
      if (msg && (msg.type === 'TOGGLE_RAIL_FROM_PAGE' || msg.type === 'OPEN_DOCK')) {
        // legacy TOGGLE_RAIL_FROM_PAGE → open/focus dock (rail removed)
        sendResponse(await openOrFocusDock(msg.reason || msg.type));
        return;
      }
      if (msg && msg.type === 'OPEN_URL' && msg.url) {
        const u = String(msg.url);
        if (/keepalive|session|main\.do/i.test(u) || msg.reason === 'keepalive') {
          sendResponse({ ok: false, error: '세션 유지 비활성(요청 없음)' });
          return;
        }
        await chrome.tabs.create({ url: u, active: true });
        sendResponse({ ok: true });
        return;
      }
      if (msg && msg.type === 'GET_TASK_CARDS') {
        const { taskCards = [] } = await chrome.storage.local.get('taskCards');
        sendResponse({ ok: true, taskCards: taskCards });
        return;
      }
      if (msg && msg.type === 'SET_BADGES') {
        await syncPinBadge();
        sendResponse({ ok: true });
        return;
      }
      if (msg && msg.type === 'AI_STATUS') {
        const prompt = await getPromptAvailability();
        const summarizer = await getSummarizerAvailability();
        sendResponse({ ok: true, prompt: prompt, summarizer: summarizer });
        return;
      }
      if (msg && msg.type === 'AI_SUMMARIZE') {
        try {
          const r = await Promise.race([
            summarizeGongmun(msg.text || ''),
            new Promise((resolve) => setTimeout(() => resolve({ ok: false, error: '요약 시간 초과', text: '', source: 'fallback' }), 25000))
          ]);
          sendResponse(r);
        } catch (e) {
          sendResponse({ ok: false, error: String((e && e.message) || e), text: '', source: 'fallback' });
        }
        return;
      }
      if (msg && msg.type === 'PIN_SET') {
        try { sendResponse(await handlePinSet(msg)); } catch (e) { sendResponse({ ok: false, error: String((e && e.message) || e) }); }
        return;
      }
      if (msg && msg.type === 'PIN_UNLOCK') {
        try { sendResponse(await handlePinUnlock(msg)); } catch (e) { sendResponse({ ok: false, error: String((e && e.message) || e) }); }
        return;
      }
      if (msg && msg.type === 'PIN_LOCK') {
        sendResponse(await lockNow());
        return;
      }
      if (msg && msg.type === 'VAULT_SAVE') {
        try { sendResponse(await handleVaultSave(msg)); } catch (e) { sendResponse({ ok: false, error: String((e && e.message) || e) }); }
        return;
      }
      if (msg && msg.type === 'VAULT_WIPE') {
        sendResponse(await handleVaultWipe(msg));
        return;
      }
      if (msg && msg.type === 'PIN_DISABLE') {
        sendResponse(await handlePinDisable(msg));
        return;
      }
      if (msg && msg.type === 'VAULT_STATUS') {
        await restorePinSession();
        const st = await chrome.storage.local.get(['pinLockEnabled', 'vaultBlob', 'penUnlockedUntil', 'pinFailCount']);
        const unlocked = !st.pinLockEnabled || (Number(st.penUnlockedUntil || 0) > Date.now() && !!memSession);
        sendResponse({
          ok: true,
          pinLockEnabled: !!st.pinLockEnabled,
          hasVault: !!st.vaultBlob,
          unlocked: unlocked || (!st.pinLockEnabled),
          hasPortalMem: !!(memSession && memSession.portal),
          hasCertMem: !!(memSession && memSession.certPassword),
          failCount: Number(st.pinFailCount || 0)
        });
        return;
      }
      if (msg && msg.type === 'PORTAL_LOGIN_NOW') {
        // Requires prior PIN_UNLOCK so memSession holds portal creds.
        sendResponse(await portalLoginFillActiveTab());
        return;
      }
      if(msg?.type==='OFFICIAL_MAIL_OPEN') {
        const locked=await requireUnlocked();if(locked){sendResponse(locked);return;}
        sendResponse(await openOfficialMail(await savedCertPassword()));return;
      }
      if(msg?.type==='EXTERNAL_OPEN') {
        const locked=await requireUnlocked();if(locked){sendResponse(locked);return;}
        sendResponse(await openExternalService(msg.serviceId));return;
      }
      if (msg?.type === 'OPEN_WORK_PAGE') {
        const locked=await requireUnlocked();if(locked){sendResponse(locked);return;}
        if(!['daily','duty','trip'].includes(msg.page)){sendResponse({ok:false,error:'지원하지 않는 업무 화면입니다.'});return;}
        const opened=await startQuickOpen('neis', await savedCertPassword());
        if(!opened.ok){sendResponse(opened);return;}
        sendResponse(await openWorkPage(msg.page));return;
      }
      if (msg && msg.type === 'QUICK_OPEN_STATUS') {
        sendResponse({ ok: true, status: await quickOpenStatus() });
        return;
      }
      if (msg && msg.type === 'QUICK_OPEN' || (msg && msg.type === 'OPEN_SITE')) {
        const locked = await requireUnlocked();
        if (locked) { sendResponse(locked); return; }
        const target = msg.target || (msg.site === 'edufine' ? 'edufine' : (msg.site === 'neis' ? 'neis' : 'portal'));
        sendResponse(await startQuickOpen(target, await savedCertPassword()));
        return;
      }
      if (msg && msg.type === 'WORKFLOW_STEP') {
        const locked = await requireUnlocked();
        if (locked) { sendResponse(locked); return; }
        sendResponse(await workflowStep(msg.action, !!msg.execute, msg.expected, msg.target));
        return;
      }
      if (msg && msg.type === 'NEIS_AUTO_ROUTE') {
        const locked = await requireUnlocked();
        if (locked) { sendResponse(locked); return; }
        const st = await chrome.storage.local.get(['dutyPresets']);
        const preset = st.dutyPresets?.[msg.index];
        if (!preset || JSON.stringify(preset) !== JSON.stringify(msg.expectedPreset)) {
          sendResponse({ok:false,error:'루틴이 변경되었습니다. 팝업을 다시 열어 확인하세요.'}); return;
        }
        sendResponse(await startNeisRoute(prepareRoute(preset,msg.overrides))); return;
      }
      if (msg && msg.type === 'APPLY_DUTY_PRESET') {
        sendResponse(await applyDutyPresetIndex(Number(msg.index), msg.overrides, msg.expectedPreset));
        return;
      }
      if (msg && msg.type === 'DIAG_INFO') {
        const st = await chrome.storage.local.get(['theme', 'keepAliveEnabled', 'dutyPresets', 'taskCards', 'todos', 'schedules']);
        const man = chrome.runtime.getManifest();
        sendResponse({
          ok: true,
          text: [
            '교직원 업무도우미 ' + (man && man.version),
            'theme=' + (st.theme || 'black'),
            'keepAlive=' + !!st.keepAliveEnabled,
            'dutyPresets=' + ((st.dutyPresets || []).length),
            'taskCards=' + ((st.taskCards || []).length),
            'todos=' + ((st.todos || []).length),
            'schedules=' + ((st.schedules || []).length),
            'fill-only · no external network · 상신/저장/결재 클릭 안 함'
          ].join('\n')
        });
        return;
      }
      if (msg && msg.type === 'AI_RANK_CARDS') {
        const { taskCards = [] } = await chrome.storage.local.get('taskCards');
        sendResponse(await rankTaskCards(msg.text || '', taskCards));
        return;
      }
      if (msg && msg.type === 'NOTICE_DRAFT') {
        const draft = newSchoolNoticeDraft(msg.title || '', msg.body || '', msg.attachments || []);
        const checklist = hwpPasteChecklist();
        const annotated = annotateOutdentLines(draft);
        sendResponse({ ok: true, draft: draft, checklist: checklist, annotated: annotated, ending: formatAttachEnding(msg.attachments || []) });
        return;
      }
      if (msg && msg.type === 'NOTICE_ATTACH_ENDING') {
        sendResponse({ ok: true, text: formatAttachEnding(msg.names || []) });
        return;
      }
      if (msg && msg.type === 'GROK_PREP') {
        const r = grokPrepPacket(msg.title || '', msg.body || '');
        await chrome.storage.local.set({ lastMaskPairs: r.pairs || [] });
        sendResponse({ ok: true, packet: r.packet, pairs: r.pairs, masked: r.masked });
        return;
      }
      if (msg && msg.type === 'GROK_POLISH') {
        // Only when user pressed — optional on-device polish of already-masked text.
        const text = msg.masked || msg.text || '';
        const polished = await polishGongmun(text);
        sendResponse(polished);
        return;
      }
      if (msg && msg.type === 'GROK_UNMASK') {
        const { lastMaskPairs = [] } = await chrome.storage.local.get('lastMaskPairs');
        const pairs = (msg.pairs && msg.pairs.length) ? msg.pairs : lastMaskPairs;
        sendResponse({ ok: true, text: unmaskPersonalInfo(msg.text || '', pairs) });
        return;
      }
      if (msg && msg.type === 'TRIP_DRAFT') {
        const draft = tripDraftFromNotice(msg.title || '', msg.body || '');
        await chrome.storage.local.set({ travelForm: {
          purpose: draft.purpose,
          place: draft.place,
          start: draft.start,
          end: draft.end,
          region: draft.region,
          transport: '',
          time: draft.time
        }});
        sendResponse({ ok: true, draft: draft });
        return;
      }
      if (msg && msg.type === 'TODO_LIST') {
        sendResponse({ ok: true, items: await listWorkItems() });
        return;
      }
      if (msg && msg.type === 'TODO_ADD') {
        const item = await addTodo({ title: msg.title, due: msg.due, body: msg.body, source: msg.source || 'manual' });
        sendResponse({ ok: true, item: item });
        return;
      }
      if (msg && msg.type === 'TODO_DONE') {
        await setTodoDone(msg.id, msg.done !== false);
        sendResponse({ ok: true });
        return;
      }
      if (msg && msg.type === 'TODO_REMOVE') {
        await removeTodo(msg.id);
        sendResponse({ ok: true });
        return;
      }
      if (msg && msg.type === 'TODO_TO_SCHED') {
        sendResponse(await registerScheduleFromTodo(msg.id));
        return;
      }
      if (msg && msg.type === 'GCAL_OPEN') {
        const title = msg.title || '일정';
        const dateYmd = msg.date || dueDateFromText(title) || '';
        const url = newGCalTemplateUrl(title, dateYmd || undefined, msg.details || '');
        const pending = { schedId: msg.schedId || null, title: title, date: dateYmd, openedAt: Date.now() };
        await chrome.storage.local.set({ pendingGcal: pending });
        await chrome.tabs.create({ url: url, active: true });
        sendResponse({ ok: true, url: url });
        return;
      }
      if (msg && msg.type === 'GCAL_MARK_SAVED') {
        if (msg.schedId) await markScheduleGoogleSaved(msg.schedId, msg.how || 'confirm');
        await chrome.storage.local.set({ pendingGcal: null });
        sendResponse({ ok: true, chip: '구글 캘린더에 저장됨' });
        return;
      }
      if (msg && msg.type === 'TODO_FROM_TEXT') {
        const title = String(msg.title || '').trim() || '할 일';
        const body = String(msg.body || '');
        const due = msg.due || dueDateFromText(title + '\n' + body);
        const item = await addTodo({ title: title, due: due, body: body, source: msg.source || 'page' });
        sendResponse({ ok: true, item: item });
        return;
      }
      if (msg && msg.type === 'DOC_CARD_PRESENT') {
        // Sole open path is ensureGlobalDock via tabs.onUpdated / focus — content only hints.
        sendResponse({ ok: true, skipped: 'global-dock-sw-only' });
        return;
      }
      if (msg && msg.type === 'DOCK_HELLO') {
        // dock.html loaded — adopt as the single global dock, or close if duplicate / no target
        let winId = Number(msg.dockWinId || 0) || (_sender && _sender.tab && _sender.tab.windowId) || 0;
        if (!winId) {
          try {
            const w = await chrome.windows.getLastFocused();
            if (w && w.id) winId = w.id;
          } catch (_) {}
        }
        await loadGlobalDock();
        if (GLOBAL_DOCK.dockWinId && GLOBAL_DOCK.dockWinId !== winId) {
          try { await chrome.windows.remove(winId); } catch (_) {}
          sendResponse({ ok: true, close: true, kept: GLOBAL_DOCK.dockWinId });
          return;
        }
        const target = await getDockTarget(winId);
        // 업무 탭이 없어도 작은창은 유지한다. 대상은 나중에 다시 찾는다.
        GLOBAL_DOCK.dockWinId = winId;
        await saveGlobalDock();
        const kept = await pruneExtraDocks(winId);
        // Preserve the user-resized dock width.
        if (target && target.tabId) await repositionGlobalDock(kept || winId);
        sendResponse({
          ok: true,
          close: false,
          dockWinId: kept || winId,
          title: target?.title || '',
          tabId: target?.tabId || 0
        });
        return;
      }
      if (msg && msg.type === 'DOCK_CLOSE_SELF') {
        const winId = Number(msg.dockWinId || 0) || (_sender && _sender.tab && _sender.tab.windowId);
        if (winId) {
          if (GLOBAL_DOCK.dockWinId === winId) {
            GLOBAL_DOCK.dockWinId = 0;
            void saveGlobalDock();
          }
          try { await chrome.windows.remove(winId); } catch (_) {}
          sendResponse({ ok: true });
        } else sendResponse({ ok: false, error: 'no-win' });
        return;
      }
      if (msg && (msg.type === 'DOCK_GET_TARGET' || msg.type === 'DOCK_GET_CARD_TAB')) {
        // DOCK_GET_CARD_TAB kept as alias for older dock.js during upgrade
        const t = await getDockTarget();
        if (!(t && t.tabId)) { sendResponse({ ok: false, error: 'no-tab' }); return; }
        sendResponse({
          ok: true,
          tabId: t.tabId,
          windowId: t.windowId || 0,
          url: t.url || '',
          title: t.title || ''
        });
        return;
      }
      if (msg && msg.type === 'DOCK_REPOSITION') {
        sendResponse(await repositionGlobalDock(Number(msg.dockWinId || 0) || null));
        return;
      }
      if (msg && msg.type === 'DOCK_DEBUG') {
        await loadGlobalDock();
        const wins = await chrome.windows.getAll({ populate: true });
        const snap = wins.map((w) => ({
          id: w.id,
          focused: !!w.focused,
          type: w.type,
          width: w.width,
          tabs: (w.tabs || []).slice(0, 3).map((tb) => ({
            id: tb.id,
            active: !!tb.active,
            url: String(tb.url || '').slice(0, 120),
            title: String(tb.title || '').slice(0, 80),
            eligible: isEligibleTargetTab(tb)
          }))
        }));
        const target = await getDockTarget(Number(msg.excludeWinId || 0) || 0);
        const out = {
          ok: true,
          global: {
            dockWinId: GLOBAL_DOCK.dockWinId,
            targetTabId: GLOBAL_DOCK.targetTabId,
            targetWinId: GLOBAL_DOCK.targetWinId
          },
          target: target,
          wins: snap
        };
        try { await chrome.storage.session.set({ penDockDebug: out }); } catch (_) {}
        sendResponse(out);
        return;
      }
      if (msg && msg.type === 'DOCK_PIN_GET') {
        await loadGlobalDock();
        sendResponse({ ok: true, pinned: !!GLOBAL_DOCK.pinned });
        return;
      }
      if (msg && msg.type === 'DOCK_PIN_SET') {
        await loadGlobalDock();
        GLOBAL_DOCK.pinned = !!msg.pinned;
        await saveGlobalDock();
        if (GLOBAL_DOCK.pinned && GLOBAL_DOCK.dockWinId) await repositionGlobalDock(GLOBAL_DOCK.dockWinId);
        sendResponse({ ok: true, pinned: !!GLOBAL_DOCK.pinned });
        return;
      }
      if (msg && msg.type === 'DOCK_COPY_DOC_NO') {
        sendResponse(await copyDocNoFromCard());
        return;
      }
      if (msg && msg.type === 'DOCK_GET_CARD_BODY') {
        sendResponse(await getCardBodyText());
        return;
      }
      if (msg && msg.type === 'DOCK_OPEN_TEST') {
        sendResponse(await ensureGlobalDock('DOCK_OPEN_TEST'));
        return;
      }
      if (msg && msg.type === 'DOCK_ACT') {
        sendResponse({ ok: true, note: 'use tab messages' });
        return;
      }
      sendResponse({ ok: false, error: 'unknown' });
    } catch (e) {
      sendResponse({ ok: false, error: String((e && e.message) || e) });
    }
  })();
  return true;
});


async function openOrFocusDock(reason) {
  try {
    const r = await ensureGlobalDock(reason || 'openOrFocusDock');
    await loadGlobalDock();
    if (GLOBAL_DOCK.dockWinId) {
      try { await chrome.windows.update(GLOBAL_DOCK.dockWinId, { focused: true }); } catch (_) {}
    }
    return r || { ok: true, dockWinId: GLOBAL_DOCK.dockWinId || null };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

chrome.commands.onCommand.addListener((command) => {
  void (async () => {
    if (command === 'toggle-rail' || command === 'open-dock') {
      await openOrFocusDock(command);
      return;
    }
    if (command === 'open-portal' || command === 'open-edufine' || command === 'open-neis') {
      const locked = await requireUnlocked();
      if (locked) return;
      const target = command === 'open-edufine' ? 'edufine' : (command === 'open-neis' ? 'neis' : 'portal');
      await startQuickOpen(target, await savedCertPassword());
      return;
    }
    if (command === 'fill-duty-preset') {
      await applyDutyPresetIndex(0);
    }
  })();
});

try {
  chrome.idle.setDetectionInterval(600); // 10 min
  chrome.idle.onStateChanged.addListener((state) => {
    if (state === 'locked') {
      void lockNow();
    }
  });
} catch (_) { /* idle API optional */ }




/* ===== 1.2.20 single global dock (one window total) ===== */
const DOCK_W = 280;
const DOCK_SESSION_KEY = 'penGlobalDock';
const GLOBAL_DOCK = {
  dockWinId: 0,
  targetTabId: 0,
  targetWinId: 0,
  lastCardTabId: 0,
  lastCardWinId: 0,
  pinned: false,
  inflight: null
};

function isOurDockUrl(url) {
  const u = String(url || '');
  try {
    return u.indexOf(chrome.runtime.getURL('dock.html')) === 0 || /chrome-extension:\/\/[^/]+\/dock\.html/i.test(u);
  } catch (_) {
    return /\/dock\.html/i.test(u);
  }
}

function isEligibleTargetUrl(url) {
  const u = String(url || '');
  if (!u || /^(chrome|edge|about|devtools|chrome-extension):/i.test(u)) return false;
  if (isOurDockUrl(u)) return false;
  // 업무포털 / 에듀파인 / 나이스 / docs
  if (/(pen\.go\.kr|eduptl\.kr|neis\.go\.kr|neis\.me|sen\.go\.kr)/i.test(u)) return true;
  return false;
}

function isDocCardUrl(url) {
  const u = String(url || '');
  if (!isEligibleTargetUrl(u)) return false;
  return /(sanctn|gwdoc|docview|docdetail|misdoc|formdoc|document|aaz|docmng|doc_?card|docinfo)/i.test(u);
}

function isDocCardTitle(title) {
  return /문서관리|문서\s*카드|기안문|문서보기|문서조회|공문/i.test(String(title || ''));
}

function isEligibleTargetTab(tab) {
  if (!tab) return false;
  if (isOurDockUrl(tab.url)) return false;
  if (isEligibleTargetUrl(tab.url)) return true;
  // WebDRM / opaque URL: fall back to known portal titles
  const title = String(tab.title || '');
  if (/에듀파인|나이스|NEIS|업무포털|전자문서|문서관리/i.test(title)) return true;
  return false;
}

async function saveGlobalDock() {
  try {
    await chrome.storage.session.set({
      [DOCK_SESSION_KEY]: {
        dockWinId: GLOBAL_DOCK.dockWinId || 0,
        targetTabId: GLOBAL_DOCK.targetTabId || 0,
        targetWinId: GLOBAL_DOCK.targetWinId || 0,
        lastCardTabId: GLOBAL_DOCK.lastCardTabId || 0,
        lastCardWinId: GLOBAL_DOCK.lastCardWinId || 0,
        pinned: !!GLOBAL_DOCK.pinned
      }
    });
  } catch (_) {}
}

async function loadGlobalDock() {
  try {
    const got = await chrome.storage.session.get(DOCK_SESSION_KEY);
    const s = (got && got[DOCK_SESSION_KEY]) || {};
    GLOBAL_DOCK.dockWinId = Number(s.dockWinId || 0) || 0;
    GLOBAL_DOCK.targetTabId = Number(s.targetTabId || 0) || 0;
    GLOBAL_DOCK.targetWinId = Number(s.targetWinId || 0) || 0;
    GLOBAL_DOCK.lastCardTabId = Number(s.lastCardTabId || 0) || 0;
    GLOBAL_DOCK.lastCardWinId = Number(s.lastCardWinId || 0) || 0;
    GLOBAL_DOCK.pinned = !!s.pinned;
  } catch (_) {}
}

async function listDockWindows() {
  const out = [];
  let wins = [];
  try { wins = await chrome.windows.getAll({ populate: true }); } catch (_) { return out; }
  for (const w of wins) {
    const tabs = (w && w.tabs) || [];
    if (tabs.some((t) => isOurDockUrl(t && t.url))) out.push(w);
  }
  return out;
}

/** Keep exactly one dock window; close extras. Prefer keepId if still open. */
async function pruneExtraDocks(keepId) {
  const docks = await listDockWindows();
  if (!docks.length) {
    GLOBAL_DOCK.dockWinId = 0;
    await saveGlobalDock();
    return 0;
  }
  let keeper = null;
  if (keepId) keeper = docks.find((w) => w.id === keepId) || null;
  if (!keeper && GLOBAL_DOCK.dockWinId) {
    keeper = docks.find((w) => w.id === GLOBAL_DOCK.dockWinId) || null;
  }
  if (!keeper) {
    // prefer already-narrow popup
    keeper = docks.find((w) => (w.width || 999) <= DOCK_W + 60) || docks[0];
  }
  for (const w of docks) {
    if (w.id !== keeper.id) {
      try { await chrome.windows.remove(w.id); } catch (_) {}
    }
  }
  GLOBAL_DOCK.dockWinId = keeper.id;
  // Preserve the user-resized dock width.
  await saveGlobalDock();
  return keeper.id;
}

async function setDockTarget(tabId, windowId) {
  if (!tabId) return false;
  let tab = null;
  try { tab = await chrome.tabs.get(tabId); } catch (_) { return false; }
  if (!(tab && isEligibleTargetTab(tab))) return false;
  if (GLOBAL_DOCK.dockWinId && tab.windowId === GLOBAL_DOCK.dockWinId) return false;
  const previous=GLOBAL_DOCK.targetTabId;
  if(previous && previous!==tab.id) await chrome.scripting.executeScript({target:{tabId:previous},func:markTargetFrame,args:[false]}).catch(()=>{});
  await chrome.scripting.executeScript({target:{tabId:tab.id},func:markTargetFrame,args:[!!GLOBAL_DOCK.dockWinId && !!(isDocCardUrl(tab.url) || isDocCardTitle(tab.title))]}).catch(()=>{});
  GLOBAL_DOCK.targetTabId = tab.id;
  GLOBAL_DOCK.targetWinId = windowId || tab.windowId || 0;
  if (isDocCardUrl(tab.url) || isDocCardTitle(tab.title)) {
    GLOBAL_DOCK.lastCardTabId = tab.id;
    GLOBAL_DOCK.lastCardWinId = GLOBAL_DOCK.targetWinId;
  }
  await saveGlobalDock();
  return true;
}

/** Prefer last-clicked 문서관리카드 for body/docno reads. */
async function getCardTarget(excludeWinId) {
  await loadGlobalDock();
  if (GLOBAL_DOCK.lastCardTabId) {
    try {
      const tab = await chrome.tabs.get(GLOBAL_DOCK.lastCardTabId);
      if (tab && isEligibleTargetTab(tab) && (isDocCardUrl(tab.url) || isDocCardTitle(tab.title)) && !(excludeWinId && tab.windowId === excludeWinId)) {
        if (!(GLOBAL_DOCK.dockWinId && tab.windowId === GLOBAL_DOCK.dockWinId)) {
          return {
            tabId: tab.id,
            windowId: tab.windowId,
            url: tab.url || '',
            title: tab.title || '',
            isCard: !!(isDocCardUrl(tab.url) || isDocCardTitle(tab.title))
          };
        }
      }
    } catch (_) {}
  }
  const t = await getDockTarget(excludeWinId);
  if (!t) return null;
  if (isDocCardUrl(t.url) || isDocCardTitle(t.title)) return {...t,isCard:true};
  // Never choose an arbitrary document when several cards are open.
  const wins=await chrome.windows.getAll({populate:true});
  const cards=wins.filter(w=>w.id!==GLOBAL_DOCK.dockWinId && w.id!==excludeWinId)
    .flatMap(w=>(w.tabs||[]).filter(tab=>isEligibleTargetTab(tab)&&(isDocCardUrl(tab.url)||isDocCardTitle(tab.title))));
  if(cards.length!==1)return null;
  const tab=cards[0];
  return {tabId:tab.id,windowId:tab.windowId,title:tab.title||'',url:tab.url||'',isCard:true};
}

async function probeFrames(tabId, msgType) {
  const results = [];
  // Prefer executeScript allFrames — works even if content listener missing in a frame
  try {
    const injected = await chrome.scripting.executeScript({
      target: { tabId: tabId, allFrames: true },
      func: (type) => {
        try {
          if (type === 'EXTRACT_DOC_NO_FRAME' && typeof window.__penHelperContentHandle === 'function') {
            return new Promise((resolve) => {
              window.__penHelperContentHandle({ type: 'EXTRACT_DOC_NO_FRAME' }, resolve);
            });
          }
        } catch (_) {}
        // inline fallback
        function collect() {
          const parts = [];
          function pushDoc(doc) {
            if (!doc) return;
            try {
              const t = (doc.body && (doc.body.innerText || doc.body.textContent)) || '';
              if (t && t.trim()) parts.push(t);
            } catch (_) {}
            try {
              for (const fr of doc.querySelectorAll('iframe,frame')) {
                try {
                  const idoc = fr.contentDocument || (fr.contentWindow && fr.contentWindow.document);
                  if (idoc) pushDoc(idoc);
                } catch (_) {}
              }
            } catch (_) {}
          }
          try { pushDoc(document); } catch (_) {}
          return parts.join('\n');
        }
        const text = collect();
        const m = text.match(/시행\s*([가-힣A-Za-z0-9·ㆍ\s]{2,60}?-\s*\d{1,8})\s*\(\s*(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})\s*\.?\s*\)/);
        if (m) {
          const id = m[1].replace(/\s+/g, '');
          const date = m[2] + '. ' + Number(m[3]) + '. ' + Number(m[4]) + '.';
          return {
            ok: true,
            value: '1. 관련: ' + id + '(' + date + ')',
            source: '시행',
            textLen: text.length,
            textSample: text.slice(0, 1500),
            title: document.title || '',
            hasCanvas: !!document.querySelector('canvas')
          };
        }
        return {
          ok: false,
          value: '',
          source: '',
          textLen: text.length,
          textSample: text.slice(0, 1500),
          title: document.title || '',
          hasCanvas: !!document.querySelector('canvas'),
          href: String(location.href || '').slice(0, 200)
        };
      },
      args: [msgType || 'EXTRACT_DOC_NO_FRAME']
    });
    for (const row of injected || []) {
      const v = row && row.result;
      if (!v) continue;
      // handle thenable from content handle
      if (v && typeof v.then === 'function') {
        try { results.push(await v); } catch (_) {}
      } else {
        results.push(v);
      }
    }
  } catch (e) {
    // fall back to top-frame message
    try {
      const r = await chrome.tabs.sendMessage(tabId, { type: msgType || 'EXTRACT_DOC_NO_FRAME' });
      if (r) results.push(r);
    } catch (_) {}
  }
  return results;
}

async function copyDocNoFromCard() {
 const card=await getCardTarget();
 if(!card?.tabId)return {ok:false,error:'읽을 문서관리카드를 선택하지 못했습니다. 여러 카드 중 해당 창에서 본문복사 후 가져오세요.'};
 await setDockTarget(card.tabId,card.windowId);
 const frames=await chrome.scripting.executeScript({target:{tabId:card.tabId,allFrames:true},func:()=>String(window.getSelection?.()||'').trim() || document.body?.innerText || ''}).catch(()=>[]);
 const hits=frames.map(f=>parseIssuedReference(f.result)).filter(r=>r.ok);
 const values=[...new Set(hits.map(r=>r.value))];
 if(values.length>1)return {ok:false,error:'서로 다른 시행번호가 보입니다. 해당 공문의 시행 줄을 원문 칸에 붙여넣어주세요.'};
 return hits[0] || parseIssuedReference('');
}

async function getCardBodyText() {
  const card=await getCardTarget();
  if(!card?.tabId)return {ok:false,error:'대상 업무 탭이 없습니다.'};
  await setDockTarget(card.tabId,card.windowId);
  const results=await chrome.scripting.executeScript({target:{tabId:card.tabId,allFrames:true},func:readDocumentContext}).catch(()=>[]);
  const matches=results.map(r=>r.result).filter(r=>r?.ok&&r.body);
  if(!matches.length)return {ok:false,error:'브라우저에서 공문 본문을 읽지 못했습니다. 문서관리카드의 본문복사 후 원문 칸에 붙여넣으세요.',body:'',title:''};
  matches.sort((a,b)=>b.body.length-a.body.length);
  return {...matches[0],tabId:card.tabId};
}

async function getDockTarget(excludeWinId) {
  const skipWin = (wid) => {
    if (!wid) return false;
    if (GLOBAL_DOCK.dockWinId && wid === GLOBAL_DOCK.dockWinId) return true;
    if (excludeWinId && wid === excludeWinId) return true;
    return false;
  };
  // Prefer remembered target if still valid
  if (GLOBAL_DOCK.targetTabId) {
    try {
      const tab = await chrome.tabs.get(GLOBAL_DOCK.targetTabId);
      if (tab && isEligibleTargetTab(tab) && !skipWin(tab.windowId)) {
        return {
          tabId: tab.id,
          windowId: tab.windowId,
          url: tab.url || '',
          title: tab.title || ''
        };
      }
    } catch (_) {}
  }
  // Fallback: last focused eligible window's active tab (never the dock itself)
  try {
    const wins = await chrome.windows.getAll({ populate: true });
    const focused = wins.find((w) => w.focused && !skipWin(w.id)) || null;
    const pool = focused ? [focused, ...wins] : wins;
    const seen = new Set();
    for (const w of pool) {
      if (!w || skipWin(w.id) || seen.has(w.id)) continue;
      seen.add(w.id);
      const tabs = w.tabs || [];
      const active = tabs.find((t) => t.active) || tabs[0];
      if (active && isEligibleTargetTab(active)) {
        GLOBAL_DOCK.targetTabId = active.id;
        GLOBAL_DOCK.targetWinId = w.id;
        await saveGlobalDock();
        return {
          tabId: active.id,
          windowId: w.id,
          url: active.url || '',
          title: active.title || ''
        };
      }
    }
  } catch (_) {}
  return null;
}

async function getFallbackWindow(excludeWinId) {
  // 업무 탭이 없어도 도킹을 띄울 수 있도록 마지막 일반 브라우저 창을 찾는다.
  try {
    const wins = await chrome.windows.getAll({ populate: false });
    const skip = (win) => !!win && ((GLOBAL_DOCK.dockWinId && win.id === GLOBAL_DOCK.dockWinId) || (excludeWinId && win.id === excludeWinId));
    return wins.find((win) => win.focused && !skip(win))
      || wins.find((win) => win.type === 'normal' && !skip(win))
      || wins.find((win) => !skip(win))
      || null;
  } catch (_) {
    return null;
  }
}

async function repositionGlobalDock(dockWinIdOpt) {
  await loadGlobalDock();
  const dockId = Number(dockWinIdOpt || GLOBAL_DOCK.dockWinId || 0);
  if (!dockId) return { ok: false, error: 'no-dock' };
  const target = await getDockTarget();
  let card = null;
  if (target && target.windowId) {
    try { card = await chrome.windows.get(target.windowId); } catch (_) { card = null; }
  }
  if (!card) {
    const fallback = await getFallbackWindow(dockId);
    if (fallback) {
      try { card = await chrome.windows.get(fallback.id); } catch (_) { card = null; }
    }
  }
  if (!card) return { ok: true, skipped: true, title: '' };
  try {
    const dockH = Math.min(720, Math.max(420, card.height || 560));
    let left = (card.left || 0) + (card.width || 900) + 6;
    let top = card.top || 80;
    if (left > 1800) left = Math.max(0, (card.left || 0) - DOCK_W - 6);
    const current = await chrome.windows.get(dockId);
    if (current.focused || current.state === 'minimized') return { ok: true, skipped: true, title: target?.title || '' };
    const bounds = { left: Math.round(left), top: Math.round(top), width: current.width || DOCK_W, height: current.height || Math.round(dockH) };
    if (Object.entries(bounds).some(([key, value]) => current[key] !== value)) {
      await chrome.windows.update(dockId, bounds);
    }
    GLOBAL_DOCK.dockWinId = dockId;
    await saveGlobalDock();
    return { ok: true, title: target?.title || '' };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

async function ensureGlobalDock(reason) {
  if (GLOBAL_DOCK.inflight) {
    try { return await GLOBAL_DOCK.inflight; } catch (e) {
      return { ok: false, error: String((e && e.message) || e) };
    }
  }
  const run = (async () => {
    await loadGlobalDock();
    const target = await getDockTarget();

    // Reuse existing single dock
    const kept = await pruneExtraDocks(GLOBAL_DOCK.dockWinId || 0);
    if (kept) {
      try {
        await chrome.windows.get(kept);
        await repositionGlobalDock(kept);
        return { ok: true, reused: true, dockWinId: kept, reason: reason || '', title: target?.title || '' };
      } catch (_) {
        GLOBAL_DOCK.dockWinId = 0;
      }
    }

    // 업무 탭이 없으면 마지막 브라우저 창 옆에 띄운다.
    let card = null;
    const windowId = (target && target.windowId) || (await getFallbackWindow())?.id || 0;
    if (windowId) {
      try { card = await chrome.windows.get(windowId); } catch (_) { card = null; }
    }
    const dockH = card ? Math.min(720, Math.max(420, card.height || 560)) : 560;
    let left = card ? (card.left || 0) + (card.width || 900) + 6 : 100;
    let top = card ? (card.top || 80) : 80;
    if (left > 1800) left = Math.max(0, ((card && card.left) || 0) - DOCK_W - 6);
    const dock = await chrome.windows.create({
      url: chrome.runtime.getURL('dock.html'),
      type: 'popup',
      width: DOCK_W,
      height: dockH,
      left: Math.round(left),
      top: Math.round(top),
      focused: false
    });
    if (!(dock && dock.id)) return { ok: false, error: 'create-failed' };
    GLOBAL_DOCK.dockWinId = dock.id;
    await saveGlobalDock();
    try {
      await chrome.windows.update(dock.id, {
        width: DOCK_W,
        height: Math.round(dockH),
        left: Math.round(left),
        top: Math.round(top),
        focused: false
      });
    } catch (_) {}
    await pruneExtraDocks(dock.id);
    return { ok: true, dockWinId: dock.id, reason: reason || '', title: target?.title || '' };
  })();
  GLOBAL_DOCK.inflight = run;
  try { return await run; } finally { GLOBAL_DOCK.inflight = null; }
}

// aliases used by older call sites during transition
async function openDockBeside(_cardWinId, reason) {
  return ensureGlobalDock(reason || 'openDockBeside');
}
async function repositionDock(_cardWinId, dockWinIdOpt) {
  return repositionGlobalDock(dockWinIdOpt);
}
async function findCardTab(cardWinId) {
  if (!cardWinId) {
    const t = await getDockTarget();
    if (!t) return null;
    try { return await chrome.tabs.get(t.tabId); } catch (_) { return null; }
  }
  const tabs = await chrome.tabs.query({ windowId: cardWinId });
  const usable = (tabs || []).filter((t) => t && !isOurDockUrl(t.url));
  return usable.find((t) => t.active) || usable[0] || null;
}

chrome.windows.onRemoved.addListener((winId) => {
  if (GLOBAL_DOCK.dockWinId === winId) {
    if(GLOBAL_DOCK.targetTabId) void chrome.scripting.executeScript({target:{tabId:GLOBAL_DOCK.targetTabId},func:markTargetFrame,args:[false]}).catch(()=>{});
    GLOBAL_DOCK.dockWinId = 0;
    void saveGlobalDock();
  }
});

if (chrome.windows.onBoundsChanged) {
  chrome.windows.onBoundsChanged.addListener((win) => {
    try {
      if (win && win.id && GLOBAL_DOCK.targetWinId === win.id && GLOBAL_DOCK.dockWinId) {
        void repositionGlobalDock(GLOBAL_DOCK.dockWinId);
      }
    } catch (_) {}
  });
}

chrome.windows.onFocusChanged.addListener((winId) => {
  if (winId === chrome.windows.WINDOW_ID_NONE) return;
  void (async () => {
    try {
      await loadGlobalDock();
      if (GLOBAL_DOCK.dockWinId && winId === GLOBAL_DOCK.dockWinId) return; // ignore dock
      const tabs = await chrome.tabs.query({ active: true, windowId: winId });
      const tab = tabs[0];
      if (!(tab && isEligibleTargetTab(tab))) return;
      await setDockTarget(tab.id, winId);
      if (GLOBAL_DOCK.dockWinId) {
        await repositionGlobalDock(GLOBAL_DOCK.dockWinId);
      } else if (isDocCardUrl(tab.url) || isDocCardTitle(tab.title)) {
        await ensureGlobalDock('onFocusChanged');
      }
    } catch (_) {}
  })();
});

chrome.tabs.onActivated.addListener((info) => {
  void (async () => {
    try {
      await loadGlobalDock();
      if (GLOBAL_DOCK.dockWinId && info.windowId === GLOBAL_DOCK.dockWinId) return;
      const tab = await chrome.tabs.get(info.tabId);
      if (!(tab && isEligibleTargetTab(tab))) return;
      await setDockTarget(tab.id, info.windowId);
      if (GLOBAL_DOCK.dockWinId) {
        await repositionGlobalDock(GLOBAL_DOCK.dockWinId);
      }
    } catch (_) {}
  })();
});

// Open/ensure single dock when a doc-like page finishes loading
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (info.status !== 'complete' && !info.title && !info.url) return;
  void (async () => {
    try {
      const url = (info.url != null ? info.url : tab.url) || '';
      const title = (info.title != null ? info.title : tab.title) || '';
      if (isOurDockUrl(url)) return;
      const probe = { url: url, title: title, id: tabId, windowId: tab.windowId };
      if (!isEligibleTargetTab(probe)) return;
      await setDockTarget(tabId, tab.windowId);
      if (!(isDocCardUrl(url) || isDocCardTitle(title))) {
        // still retarget/reposition if dock already open
        if (GLOBAL_DOCK.dockWinId) await repositionGlobalDock(GLOBAL_DOCK.dockWinId);
        return;
      }
      let win = null;
      try { win = await chrome.windows.get(tab.windowId); } catch (_) { return; }
      const strong = isDocCardTitle(title);
      if (!(strong || win.type === 'popup' || win.type === 'app')) return;
      try {
        await chrome.storage.session.set({ penDockLastTrigger: { reason: 'tabs.onUpdated', url: url, title: title, at: Date.now() } });
      } catch (_) {}
      await ensureGlobalDock('tabs.onUpdated');
    } catch (_) {}
  })();
});

// Boot: hydrate + close extras from prior buggy double-open
void (async () => {
  try {
    await loadGlobalDock();
    await pruneExtraDocks(GLOBAL_DOCK.dockWinId || 0);
  } catch (_) {}
})();
