import './lib/start-lock.js';
import { DEFAULT_EXTERNAL_SERVICES } from './lib/external-services.js';

const status = document.getElementById('status');
const externalWrap = document.getElementById('externalServices');

function setStatus(text) {
  status.textContent = text || '';
}

function renderServices(services) {
  const list = Array.isArray(services) ? services : [];
  if (!list.length) {
    const empty = document.createElement('p');
    empty.className = 'external-empty';
    empty.textContent = '설정에서 외부 서비스를 추가할 수 있습니다.';
    externalWrap.replaceChildren(empty);
    return;
  }
  externalWrap.replaceChildren(...list.map((service) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'external-service';
    button.dataset.service = service.id;
    const name = document.createElement('strong');
    name.textContent = service.name || '외부 서비스';
    const method = document.createElement('span');
    let insecure = false;
    try { insecure = new URL(service.domain).protocol === 'http:'; } catch (_) {}
    method.textContent = (service.method === 'certificate' ? '인증서 로그인' : '아이디·비밀번호 로그인')
      + (insecure ? ' · SSL 미지원' : '');
    button.append(name, method);
    return button;
  }));
}

async function loadServices() {
  try {
    const { externalServices } = await chrome.storage.local.get('externalServices');
    if (Array.isArray(externalServices)) {
      renderServices(externalServices);
      return;
    }
    await chrome.storage.local.set({ externalServices: DEFAULT_EXTERNAL_SERVICES });
    renderServices(DEFAULT_EXTERNAL_SERVICES);
  } catch (_) {
    renderServices(DEFAULT_EXTERNAL_SERVICES);
  }
}

async function runAction(action) {
  const quickOpen = ['neis', 'edufine', 'portal'].includes(action);
  const result = quickOpen
    ? await chrome.runtime.sendMessage({ type: 'QUICK_OPEN', target: action })
    : await chrome.runtime.sendMessage({ type: 'OPEN_WORK_PAGE', page: action });
  if (!result?.ok) throw new Error(result?.error || '화면을 열지 못했습니다.');
  return result.message || '화면을 열었습니다.';
}

document.addEventListener('click', async (event) => {
  const serviceButton = event.target.closest('button[data-service]');
  if (serviceButton) {
    if (serviceButton.disabled) return;
    const serviceButtons = [...document.querySelectorAll('button[data-service]')];
    serviceButtons.forEach((button) => { button.disabled = true; });
    setStatus('외부 서비스를 여는 중…');
    try {
      const result = await chrome.runtime.sendMessage({ type: 'EXTERNAL_OPEN', serviceId: serviceButton.dataset.service });
      if (!result?.ok) throw new Error(result?.error || '외부 서비스를 열지 못했습니다.');
      const message = result.message || '외부 서비스를 열었습니다.';
      setStatus(result.warning ? message + ' ' + result.warning : message);
    } catch (e) {
      setStatus(e.message);
    } finally {
      serviceButtons.forEach((button) => { button.disabled = false; });
    }
    return;
  }
  const button = event.target.closest('button[data-action]');
  if (!button) return;
  const action = button.dataset.action;
  if (action === 'settings') {
    try { await chrome.runtime.openOptionsPage(); } catch (e) { setStatus('설정을 열지 못했습니다: ' + e.message); }
    return;
  }
  const buttons = [...document.querySelectorAll('main button, .popup-footer button')];
  buttons.forEach((item) => { item.disabled = true; });
  setStatus('업무 화면을 여는 중…');
  try {
    setStatus(await runAction(action));
  } catch (e) {
    setStatus(e.message);
  } finally {
    buttons.forEach((item) => { item.disabled = false; });
  }
});

const dockButton = document.getElementById('btnOpenDock');
dockButton.addEventListener('click', async () => {
  if (dockButton.disabled) return;
  dockButton.disabled = true;
  setStatus('교직원 업무도우미 작은창을 여는 중…');
  try {
    const result = await chrome.runtime.sendMessage({ type: 'OPEN_DOCK', reason: 'popup-button' });
    if (!result?.ok) throw new Error(result?.error || '작은창을 열지 못했습니다.');
    window.close();
  } catch (e) {
    setStatus(e.message);
    dockButton.disabled = false;
  }
});

void loadServices();
