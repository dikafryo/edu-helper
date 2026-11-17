/* PEN_HELPER_EXT_VERSION=1.2.24 */
(function () {
  if (window.__penHelperContentLoaded) return;
  window.__penHelperContentLoaded = true;

// 교직원 업무도우미 content — fill only, never click 상신/저장/결재/접수/확인
var BLOCK_LABEL = /(상신|저장|결재|접수|확인|제출|승인|반려)/;

function visible(el) {
  if (!el) return false;
  const st = getComputedStyle(el);
  return st.display !== 'none' && st.visibility !== 'hidden' && el.offsetParent !== null;
}

function labelOf(el) {
  const id = el.id;
  if (id) {
    const lab = document.querySelector(`label[for="${CSS.escape(id)}"]`);
    if (lab) return lab.textContent || '';
  }
  return (el.getAttribute('aria-label') || el.name || el.placeholder || el.id || '').toString();
}

function setValue(el, value) {
  if (value == null || value === '') return false;
  if (!el || !visible(el) || el.disabled || el.readOnly) return false;
  const tag = (el.tagName || '').toLowerCase();
  let expected;
  if (tag === 'select') {
    const opts = [...el.options];
    const exact = opts.filter(o => !o.disabled && (o.text.trim() === String(value).trim() || o.value === String(value)));
    const partial = opts.filter(o => !o.disabled && o.text.includes(String(value)));
    const hit = exact.length === 1 ? exact[0] : (exact.length === 0 && partial.length === 1 ? partial[0] : null);
    if (!hit) return false;
    el.value = hit.value;
    expected = hit.value;
  } else if (el.type === 'checkbox' || el.type === 'radio') {
    el.checked = Boolean(value);
    expected = Boolean(value);
  } else {
    el.value = String(value);
    expected = String(value);
  }
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return (el.type === 'checkbox' || el.type === 'radio') ? el.checked === expected : el.value === expected;
}

function fillByHints(data, hints) {
  let filled = 0;
  const used = new Set();
  const fields = [...document.querySelectorAll('input, textarea, select')].filter(visible);
  for (const [key, value] of Object.entries(data || {})) {
    const patterns = hints[key] || [key];
    for (const el of fields) {
      if (used.has(el) || el.disabled || el.readOnly || /^(checkbox|radio|password|hidden|submit|button|file)$/i.test(el.type || '')) continue;
      const lab = labelOf(el);
      if (patterns.some((p) => lab.includes(p) || (el.name || '').includes(p) || (el.id || '').includes(p))) {
        if (setValue(el, value)) { used.add(el); filled++; break; }
      }
    }
  }
  return filled;
}


function looksLikePortalLoginPage() {
  const host = location.hostname || '';
  if (!(host === 'eduptl.kr' || host.endsWith('.eduptl.kr'))) return false;
  const passwords = [...document.querySelectorAll('input')].filter(visible).filter((el) => (el.type || '').toLowerCase() === 'password');
  return passwords.length === 1;
}

function findLoginFields() {
  const inputs = [...document.querySelectorAll('input')].filter(visible);
  const pw = inputs.find((el) => (el.type || '').toLowerCase() === 'password') || null;
  let id = null;
  if (pw) {
    // prefer previous text/email near password
    const candidates = inputs.filter((el) => {
      const t = (el.type || 'text').toLowerCase();
      return t === 'text' || t === 'email' || t === 'tel' || t === '';
    });
    id = candidates.find((el) => {
      const lab = (labelOf(el) + ' ' + (el.name || '') + ' ' + (el.id || '') + ' ' + (el.placeholder || '')).toLowerCase();
      return /id|user|login|아이디|계정|회원/.test(lab);
    }) || null;
  }
  return { id, pw };
}

function findPasswordLoginButton() {
  const buttons = [...document.querySelectorAll('button, input[type=submit], input[type=button]')].filter(visible);
  const hits = buttons.filter((el) => {
    const t = (el.innerText || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
    return t === '로그인' || /^login$/i.test(t);
  });
  return hits.length === 1 ? hits[0] : null;
}

function portalLoginFill(id, password) {
  // Password-based login only. Never click 상신/저장/결재/접수. Login button allowed.
  if (!looksLikePortalLoginPage()) {
    return { ok: false, error: '로그인 화면이 아님' };
  }
  const fields = findLoginFields();
  if (!fields.pw) return { ok: false, error: '아이디/비밀번호 칸 없음(인증서·2FA는 직접)', certLikely: true };
  if (!fields.id) {
    try { fields.pw.focus(); } catch (_) {}
    return { ok: false, error: '아이디 칸을 특정하지 못했습니다. 직접 입력하세요.' };
  }
  const okId = setValue(fields.id, id);
  const okPw = setValue(fields.pw, password);
  if (!(okId && okPw)) {
    try { fields.id.focus(); } catch (_) {}
    return { ok: false, error: '입력 칸에 값을 넣지 못함' };
  }
  const btn = findPasswordLoginButton();
  if (!btn) {
    try { fields.pw.focus(); } catch (_) {}
    return { ok: true, filled: true, clicked: false, note: '로그인 버튼 없음 · 직접 클릭' };
  }
  try {
    btn.click();
    return { ok: true, filled: true, clicked: true };
  } catch (_) {
    return { ok: true, filled: true, clicked: false, note: '클릭 실패 · 직접 클릭' };
  }
}

function collectLocalText() {
  const parts = [];
  function pushDoc(doc) {
    if (!doc) return;
    try {
      const t = (doc.body && (doc.body.innerText)) || '';
      if (t && t.trim()) parts.push(t);
    } catch (_) {}
    try {
      const nodes = doc.querySelectorAll('iframe,frame');
      for (const fr of nodes) {
        try {
          const idoc = fr.contentDocument || (fr.contentWindow && fr.contentWindow.document);
          if (idoc) pushDoc(idoc);
        } catch (_) { /* cross-origin */ }
      }
    } catch (_) {}
  }
  try { pushDoc(document); } catch (_) {}
  // canvas-only viewers leave little text — still return what we have
  return parts.join('\n');
}

function normalizeSihaengDate(y, m, d) {
  return String(y) + '. ' + String(Number(m)) + '. ' + String(Number(d)) + '.';
}

/** Parse "시행 …-번호 ( YYYY. M. D.)" → clipboard line. */
function parseSihaengRelated(text) {
  const raw = String(text || '');
  // 시행 미래인재양성사업단-2842 ( 2026. 10. 29.)
  let m = raw.match(/시행\s*([가-힣A-Za-z0-9·ㆍ\s]{2,60}?-\s*\d{1,8})\s*\(\s*(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})\s*\.?\s*\)/);
  if (m) {
    const id = m[1].replace(/\s+/g, '').replace(/-$/, '');
    const date = normalizeSihaengDate(m[2], m[3], m[4]);
    return {
      ok: true,
      value: '1. 관련: ' + id + '(' + date + ')',
      docId: id,
      date: date,
      source: '시행'
    };
  }
  // looser: 시행 … then number then date nearby
  m = raw.match(/시행\s*([^\n\r]{4,80}?\d{2,8})[^\n\r]{0,20}?\(\s*(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})\s*\.?\s*\)/);
  if (m) {
    let id = m[1].replace(/^시행\s*/, '').trim();
    id = id.replace(/\s+/g, '');
    // keep org-number pattern
    const idm = id.match(/([가-힣A-Za-z0-9·ㆍ]+-\d{1,8})/);
    if (idm) id = idm[1];
    const date = normalizeSihaengDate(m[2], m[3], m[4]);
    return {
      ok: true,
      value: '1. 관련: ' + id + '(' + date + ')',
      docId: id,
      date: date,
      source: '시행'
    };
  }
  return null;
}

function extractFromMetaFields() {
  // 결재정보 / card metadata fallbacks
  const bodyText = collectLocalText();
  const tryPairs = [
    [/문서\s*번호\s*[:：]?\s*([가-힣A-Za-z0-9·ㆍ\-_/]+)/, /시행\s*일(?:자)?\s*[:：]?\s*(\d{4})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})/],
    [/문서번호\s*[:：]?\s*([가-힣A-Za-z0-9·ㆍ\-_/]+)/, /(?:시행|등록)\s*일(?:자)?\s*[:：]?\s*(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})/]
  ];
  for (const [reNo, reDate] of tryPairs) {
    const mn = bodyText.match(reNo);
    const md = bodyText.match(reDate);
    if (mn && md) {
      const id = mn[1].trim().replace(/\s+/g, '');
      const date = normalizeSihaengDate(md[1], md[2], md[3]);
      return {
        ok: true,
        value: '1. 관련: ' + id + '(' + date + ')',
        docId: id,
        date: date,
        source: '결재정보'
      };
    }
  }
  // inputs/labels
  const el = document.querySelector('[id*="docNo"],[name*="docNo"],[id*="doc_no"],[name*="doc_no"],[id*="sanctn"],[id*="docNumber"]');
  if (el) {
    const v = (el.value || el.textContent || '').trim();
    if (v && /-\d+/.test(v)) {
      return {
        ok: true,
        value: '1. 관련: ' + v.replace(/\s+/g, ''),
        docId: v,
        date: '',
        source: 'metadata-field'
      };
    }
  }
  return null;
}

function extractDocNoResult() {
  const text = collectLocalText();
  const fromSihaeng = parseSihaengRelated(text);
  if (fromSihaeng) return fromSihaeng;
  const fromMeta = extractFromMetaFields();
  if (fromMeta) return fromMeta;
  // canvas-heavy page: little text
  const hasCanvas = !!document.querySelector('canvas');
  return {
    ok: false,
    error: '시행 번호를 찾지 못했어요',
    source: hasCanvas ? 'canvas' : 'none'
  };
}

function extractDocNo() {
  const r = extractDocNoResult();
  return (r && r.ok && (r.docId || r.value)) ? (r.docId || r.value) : '';
}

function formatRelatedDoc(docNo) {
  // legacy helper — prefer extractDocNoResult().value
  const r = extractDocNoResult();
  if (r && r.ok && r.value) return r.value;
  if (!docNo) return '';
  return '1. 관련: ' + String(docNo).replace(/\s+/g, '');
}

function fillLinesSequential(lines) {
  const vals = (lines || []).map((s) => String(s == null ? '' : s).trim()).filter((s) => s.length);
  if (!vals.length) return 0;
  const fields = [...document.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea')]
    .filter(visible)
    .filter((el) => !el.disabled && !el.readOnly);
  let filled = 0;
  let i = 0;
  for (const el of fields) {
    if (i >= vals.length) break;
    const cur = (el.value || '').trim();
    if (cur) continue; // only empty fields — fill-only, never overwrite
    if (setValue(el, vals[i])) { filled++; i++; }
  }
  return filled;
}

function scanBadges() {
  // removed: portal badge/count scraping was unreliable
  return { approve: 0, gonglam: 0, messenger: 0, sendWait: 0 };
}

function pageText() {
  return (document.title || '') + '\n' + ((document.body && document.body.innerText) || '').slice(0, 12000);
}

function scoreCard(card, text) {
  const raw = (text || '').toLowerCase();
  let score = 0;
  const name = String(card.name || '');
  if (name && raw.includes(name.toLowerCase())) score += 40;
  for (const kw of (card.keywords || [])) {
    const k = String(kw || '').trim();
    if (k && raw.includes(k.toLowerCase())) score += 12;
  }
  return score;
}

async function handleMessage(msg) {
  if ((msg && msg.type) === 'SOFT_KEEPALIVE') return { ok: true, passive: true }; // no fetch/nav
  if ((msg && msg.type) === 'SCAN_BADGES') return { ok: false, error: 'badges-removed' };
  if ((msg && msg.type) === 'COPY_DOC_NO') {
    const r = extractDocNoResult();
    if (r && r.ok && r.value) return { ok: true, value: r.value, source: r.source || '시행', docId: r.docId || '', date: r.date || '' };
    return { ok: false, error: (r && r.error) || '시행 번호를 찾지 못했어요', source: (r && r.source) || '' };
  }
  if ((msg && msg.type) === 'EXTRACT_DOC_NO_FRAME') {
    // per-frame probe for background aggregation
    const r = extractDocNoResult();
    const text = collectLocalText();
    return {
      ok: !!(r && r.ok),
      value: (r && r.value) || '',
      source: (r && r.source) || '',
      error: (r && r.error) || '',
      textLen: text.length,
      textSample: text.slice(0, 1500),
      hasCanvas: !!document.querySelector('canvas'),
      title: document.title || '',
      href: String(location.href || '').slice(0, 200)
    };
  }
  if ((msg && msg.type) === 'GET_CARD_BODY') {
    const title = (document.title || '').trim();
    const body = collectLocalText().slice(0, 20000);
    return { ok: true, title: title, body: body, textLen: body.length, hasCanvas: !!document.querySelector('canvas') };
  }
  if ((msg && msg.type) === 'GET_PAGE_TEXT') return { ok: true, text: pageText() };
  if ((msg && msg.type) === 'FILL_TRAVEL') {
    const filled = fillByHints(msg.data, {
      purpose: ['목적', '출장목적', '사유', '출장사유'],
      place: ['장소', '출장지', '행선'],
      start: ['시작', '출발', '시작일', '시작일자'],
      end: ['종료', '도착', '종료일', '종료일자'],
      region: ['출장종류', '구분', '관내', '관외'],
      transport: ['교통', '이동수단'],
      time: ['시간', '시각']
    });
    return { ok: true, filled };
  }
  if ((msg && msg.type) === 'GET_TITLE_BODY') {
    const title = (document.title || '').trim();
    const body = collectLocalText().slice(0, 20000);
    return { ok: true, title: title, body: body };
  }
  if ((msg && msg.type) === 'FILL_DUTY') {
    const filled = fillByHints(msg.data, {
      type: ['복무', '종류', '구분', '근무상황'],
      start: ['시작', '시작일', '시작일시'],
      end: ['종료', '종료일', '종료일시'],
      time: ['시각', '시간', '근무시간'],
      reason: ['사유', '내용', '비고', '신청사유']
    });
    return { ok: true, filled };
  }
  if ((msg && msg.type) === 'COPY_RELATED') {
    const r = extractDocNoResult();
    if (!(r && r.ok && r.value)) return { ok: false, error: (r && r.error) || '시행 번호를 찾지 못했어요' };
    return { ok: true, value: r.docId || r.value, related: r.value, source: r.source || '' };
  }
  if ((msg && msg.type) === 'FILL_LINES') {
    const filled = fillLinesSequential(msg.lines || []);
    return { ok: true, filled };
  }
  if ((msg && msg.type) === 'PORTAL_LOGIN_FILL') {
    return portalLoginFill(msg.id || '', msg.password || '');
  }
  if ((msg && msg.type) === 'MATCH_TASK_CARDS') {
    const { taskCards = [] } = await chrome.storage.local.get('taskCards');
    const text = pageText();
    const candidates = (taskCards || [])
      .map((c) => ({ ...c, score: scoreCard(c, text) }))
      .filter((c) => c.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 5);
    return { ok: true, candidates };
  }
  if ((msg && msg.type) === 'FILL_TASK_CARD') {
    const card = msg.card || {};
    const filled = fillByHints({
      card: card.name,
      owner: (card.owners || [])[0] || card.owner || ''
    }, {
      card: ['과제카드', '단위사업', '사업카드', '카드'],
      owner: ['담당', '담당자']
    });
    return { ok: true, filled };
  }
  return { ok: false, error: 'unknown' };
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    try { sendResponse(await handleMessage(msg)); }
    catch (e) { sendResponse({ ok: false, error: String(e.message || e) }); }
  })();
  return true;
});

// Remove leftover rail host from older builds (no in-page UI)
try {
  const stale = document.getElementById('pen-helper-rail-host');
  if (stale && stale.parentNode) stale.parentNode.removeChild(stale);
  const peek = document.getElementById('pen-helper-peeker');
  if (peek && peek.parentNode) peek.parentNode.removeChild(peek);
} catch (_) {}

console.debug('[교직원 업무도우미] content ready (fill-only · dock only)');

// Copy only an explicitly identified document-title cell on a real user click.
document.addEventListener('click', event => {
 if(!event.isTrusted)return;
 const cell=event.target.closest?.('td,[role="gridcell"]');
 const row=cell?.closest('tr,[role="row"]');
 const grid=row?.closest('table,[role="grid"]');
 if(!cell || !grid)return;
 const headers=[...grid.querySelectorAll('thead th,[role="columnheader"]')];
 const index=headers.findIndex(h=>/^(문서)?제목$/.test((h.innerText||'').replace(/\s/g,'')));
 const cells=[...row.querySelectorAll('td,[role="gridcell"]')];
 if(index<0 || cells[index]!==cell)return;
 const title=(cell.innerText||'').trim();
 if(!title || title.length>500)return;
 const value=/안내$/.test(title)?title:title+' 안내';
 void chrome.runtime.sendMessage({type:'NOTICE_TITLE_SELECTED',title}).catch(()=>{});
 void navigator.clipboard.writeText(value).catch(()=>{});
},true);

})();
