async function run(type, extra) {
  const out = document.getElementById('out');
  try {
    const r = await chrome.runtime.sendMessage(Object.assign({ type }, extra || {}));
    const text = JSON.stringify(r, null, 2);
    out.textContent = text;
    document.title = 'pen diag · ' + type + ' · ' + (r && r.ok ? 'ok' : 'fail') + (r && r.error ? ' · ' + r.error : '') + (r && r.target ? ' · tab' + r.target.tabId : '');
    return r;
  } catch (e) {
    out.textContent = String(e);
    document.title = 'pen diag · err · ' + e;
    return null;
  }
}
document.getElementById('btnDebug').onclick = () => { void run('DOCK_DEBUG'); };
document.getElementById('btnOpen').onclick = () => { void run('OPEN_DOCK', { reason: 'diag' }); };
document.getElementById('btnTest').onclick = () => { void run('DOCK_OPEN_TEST'); };
document.getElementById('btnCopy').onclick = () => { void run('DOCK_COPY_DOC_NO'); };
void (async () => {
  await run('DOCK_DEBUG');
})();
