const panels = [...document.querySelectorAll('[data-settings-panel]')];
function navigate() {
  const requested = location.hash.slice(1) || 'start';
  const active = panels.some(p => p.dataset.settingsPanel === requested) ? requested : 'start';
  for (const panel of panels) panel.hidden = panel.dataset.settingsPanel !== active;
  document.querySelectorAll('.settings-sidebar a').forEach(a => {
    if (a.hash === '#' + active) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  });
}
window.addEventListener('hashchange', navigate);
navigate();
const manifest = chrome.runtime.getManifest();
document.getElementById('settingsVersion').textContent = `${manifest.name} · ${manifest.version}`;
function list(id, values) {
  document.getElementById(id).replaceChildren(...values.map(value => {
    const item = document.createElement('li'); item.textContent = value; return item;
  }));
}
list('permissionList', manifest.permissions || []);
list('hostList', manifest.host_permissions || []);
chrome.commands.getAll().then(commands => list('shortcutList', commands.map(c => `${c.description || c.name}: ${c.shortcut || '미지정'}`))).catch(() => list('shortcutList', ['단축키를 불러오지 못했습니다.']));
const theme = document.getElementById('settingsTheme');
chrome.storage.local.get('theme').then(data => { theme.value = data.theme || 'sky'; });
theme.addEventListener('change', async () => {
  const status = document.getElementById('themeStatus');
  try { await chrome.storage.local.set({ theme: theme.value }); status.textContent = '저장했습니다. 팝업을 다시 열면 적용됩니다.'; }
  catch { status.textContent = '저장하지 못했습니다. 다시 시도하세요.'; }
});
