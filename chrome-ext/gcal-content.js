/* Google Calendar TEMPLATE tab helper — detect save / confirm chip. No network from here. */
(function () {
  if (window.__penGcalChip) return;
  window.__penGcalChip = true;
  chrome.storage.local.get('pendingGcal').then(function (o) {
    var p = o && o.pendingGcal;
    var fresh = p && p.openedAt && (Date.now() - p.openedAt) < 30 * 60 * 1000;
    if (fresh) penGcalMain();
  }).catch(function () {});
  function penGcalMain() {

  function looksSaved() {
    try {
      const title = document.title || '';
      if (/Google 캘린더|Google Calendar|캘린더 -/i.test(title) && !/이벤트 세부|Event details|새 일정|Create/i.test(title)) {
        return true;
      }
      const blob = (document.body && document.body.innerText) ? document.body.innerText.slice(0, 4000) : '';
      if (/일정이 저장|Event saved|Saved|저장됨|일정을 저장/.test(blob)) return true;
    } catch (_) {}
    return false;
  }

  function chip(text, ok) {
    let el = document.getElementById('pen-gcal-chip');
    if (!el) {
      el = document.createElement('div');
      el.id = 'pen-gcal-chip';
      el.setAttribute('role', 'status');
      el.style.cssText = 'position:fixed;z-index:2147483646;right:16px;bottom:16px;padding:10px 14px;border-radius:999px;font:600 13px/1.3 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.18);cursor:pointer;';
      document.documentElement.appendChild(el);
    }
    el.textContent = text;
    el.style.background = ok ? '#34C759' : '#1d1d1f';
    el.style.color = '#fff';
    return el;
  }

  async function markSaved(how) {
    try {
      const { pendingGcal } = await chrome.storage.local.get('pendingGcal');
      if (pendingGcal && pendingGcal.schedId) {
        await chrome.runtime.sendMessage({ type: 'GCAL_MARK_SAVED', schedId: pendingGcal.schedId, how: how || 'detect' });
      }
    } catch (_) {}
    chip('구글 캘린더에 저장됨', true);
  }

  const confirm = chip('저장했으면 클릭 · 또는 자동 감지', false);
  confirm.addEventListener('click', function () { markSaved('confirm'); });

  let tries = 0;
  const timer = setInterval(function () {
    tries++;
    if (looksSaved()) {
      clearInterval(timer);
      markSaved('detect');
    }
    if (tries > 90) clearInterval(timer); // ~45s
  }, 500);
  }
})();
