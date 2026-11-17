const $ = (id) => document.getElementById(id);
const SSL_WARNING = '이 서비스는 SSL 보안이 지원되지 않습니다. 아이디·비밀번호가 암호화되지 않은 채 전송될 수 있습니다.';

import { validateSettings } from './lib/settings.js';
import './lib/settings-navigation.js';
import { renderRoutines } from './lib/routine-editor.js';
import { DEFAULT_EXTERNAL_SERVICES, normalizeService, normalizeServiceUrl } from './lib/external-services.js';

function setVaultStatus(t) {
  const el = $('vaultStatus');
  if (el) el.textContent = t || '';
}

async function refreshCertStatus() {
  try {
    const { certPassword = '' } = await chrome.storage.local.get('certPassword');
    setVaultStatus(certPassword
      ? '인증서 비밀번호가 저장되어 있습니다. 새로 입력하면 바꿀 수 있습니다.'
      : '아직 저장된 인증서 비밀번호가 없습니다.');
  } catch (_) {
    setVaultStatus('저장 상태를 확인하지 못했습니다.');
  }
}

async function loadJson() {
  const data = await chrome.storage.local.get(['taskCards', 'travelForm', 'dutyForm', 'dutyPresets']);
  $('cards').value = JSON.stringify(data.taskCards || [], null, 2);
  $('travel').value = JSON.stringify(data.travelForm || {}, null, 2);
  $('duty').value = JSON.stringify(data.dutyForm || {}, null, 2);
  $('presets').value = JSON.stringify(data.dutyPresets || [], null, 2);
  if (Array.isArray(data.dutyPresets || [])) renderRoutines(data.dutyPresets || []);
  await refreshCertStatus();
  try { renderServices(await getServices()); } catch (_) { setServiceStatus('서비스 목록을 불러오지 못했습니다.'); }
}

$('save').addEventListener('click', async () => {
  try {
    const settings = validateSettings({
      taskCards: JSON.parse($('cards').value || '[]'),
      travelForm: JSON.parse($('travel').value || '{}'),
      dutyForm: JSON.parse($('duty').value || '{}'),
      dutyPresets: JSON.parse($('presets').value || '[]')
    });
    await chrome.storage.local.set({ ...settings, dutyPresetsSeeded: true });
    renderRoutines(settings.dutyPresets);
    $('msg').textContent = 'JSON 저장됨';
  } catch (e) {
    $('msg').textContent = 'JSON 오류: ' + String((e && e.message) || e);
  }
});

function setServiceStatus(t) {
  const el = $('serviceStatus');
  if (el) el.textContent = t || '';
}

async function getServices() {
  const { externalServices } = await chrome.storage.local.get('externalServices');
  if (Array.isArray(externalServices)) return externalServices;
  const seeded = DEFAULT_EXTERNAL_SERVICES.map((service) => ({ ...service }));
  await chrome.storage.local.set({ externalServices: seeded });
  return seeded;
}

function renderServices(services) {
  const wrap = $('serviceList');
  const list = Array.isArray(services) ? services : [];
  if (!list.length) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = '등록된 외부 서비스가 없습니다.';
    wrap.replaceChildren(empty);
    return;
  }
  wrap.replaceChildren(...list.map((service) => {
    const row = document.createElement('div');
    row.className = 'service-item';
    const info = document.createElement('div');
    const name = document.createElement('strong');
    name.textContent = service.name || '외부 서비스';
    const detail = document.createElement('p');
    detail.className = 'muted';
    let insecure = false;
    try { insecure = new URL(service.domain).protocol === 'http:'; } catch (_) {}
    detail.textContent = `${service.domain} · ${service.method === 'certificate' ? '인증서' : '아이디·비밀번호'}${insecure ? ' · SSL 미지원' : ''}`;
    info.append(name, detail);
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.dataset.remove = service.id;
    remove.dataset.name = service.name || '외부 서비스';
    remove.textContent = '삭제';
    row.append(info, remove);
    return row;
  }));
}

$('serviceMethod').addEventListener('change', () => {
  $('serviceCredRow').hidden = $('serviceMethod').value === 'certificate';
});

$('serviceDomain').addEventListener('input', () => {
  const typed = $('serviceDomain').value.trim();
  if (typed.toLowerCase().startsWith('http://')) setServiceStatus(SSL_WARNING);
  else if ($('serviceStatus').textContent === SSL_WARNING) setServiceStatus('');
});

$('btnAddService').addEventListener('click', async () => {
  let url;
  try {
    url = normalizeServiceUrl($('serviceDomain').value);
  } catch (e) {
    setServiceStatus(e.message);
    return;
  }
  const name = $('serviceName').value.trim();
  if (!name) {
    setServiceStatus('서비스명을 입력하세요.');
    return;
  }
  const method = $('serviceMethod').value === 'certificate' ? 'certificate' : 'password';
  const insecure = url.protocol === 'http:';
  const userId = $('serviceId').value.trim();
  const password = $('servicePassword').value;
  if (method === 'password' && (!userId || !password)) {
    setServiceStatus('아이디와 비밀번호를 모두 입력하세요.');
    return;
  }
  // 사용자 클릭 직후에 권한을 요청해야 Chrome이 허용 창을 띄운다.
  try {
    await chrome.permissions.request({ origins: [url.origin + '/*'] });
  } catch (_) { /* 권한이 없으면 자동 로그인만 제한된다. */ }
  try {
    const service = normalizeService({
      id: 'svc_' + Date.now().toString(36),
      name,
      domain: $('serviceDomain').value,
      method,
      userId,
      password
    });
    const current = await getServices();
    if (current.some((item) => item.name === service.name)) {
      setServiceStatus('같은 이름의 서비스가 이미 있습니다.');
      return;
    }
    const next = [...current, service];
    await chrome.storage.local.set({ externalServices: next });
    renderServices(next);
    $('serviceName').value = '';
    $('serviceDomain').value = '';
    $('serviceId').value = '';
    $('servicePassword').value = '';
    setServiceStatus('서비스를 추가했습니다. 팝업을 다시 열면 표시됩니다.'
      + (insecure ? ' ' + SSL_WARNING : ''));
  } catch (e) {
    setServiceStatus(String((e && e.message) || e));
  }
});

$('serviceList').addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-remove]');
  if (!button) return;
  if (!confirm(`'${button.dataset.name}' 서비스를 삭제할까요?`)) return;
  const current = await getServices();
  const next = current.filter((service) => service.id !== button.dataset.remove);
  await chrome.storage.local.set({ externalServices: next });
  renderServices(next);
  setServiceStatus('서비스를 삭제했습니다.');
});

$('btnSaveCert').addEventListener('click', async () => {
  const password = $('certPw').value;
  const confirmPassword = $('certPw2').value;
  if (!password) {
    setVaultStatus('인증서 비밀번호를 입력하세요.');
    return;
  }
  if (password !== confirmPassword) {
    setVaultStatus('두 비밀번호가 다릅니다. 다시 확인해 주세요.');
    return;
  }
  try {
    // 이 브라우저 안에만 저장하고 화면에는 다시 표시하지 않는다.
    await chrome.storage.local.set({ certPassword: password });
    $('certPw').value = '';
    $('certPw2').value = '';
    setVaultStatus('인증서 비밀번호를 저장했습니다.');
  } catch (e) {
    setVaultStatus('저장하지 못했습니다: ' + String((e && e.message) || e));
  }
});

void loadJson();
