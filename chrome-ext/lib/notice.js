import { parseIssuedReference } from './document-context.js';
/**
 * 안내공문 helpers (browser text/copy only).
 * HWP window automation (굴림 12pt / Alt+Tab 내어쓰기 / 자간) is NOT available
 * from a Chrome extension — we emit formatted text + a paste checklist instead.
 */

export function fileNameWithoutExt(name) {
  const s = String(name || '').trim();
  if (!s) return '';
  return s.replace(/\.[A-Za-z0-9]{1,5}$/, '');
}

/** 붙임 numbering ending (standalone Format-NoticeAttachBodyEnding). */
export function formatAttachEnding(names) {
  const clean = [];
  for (const raw of names || []) {
    const base = fileNameWithoutExt(raw);
    if (base) clean.push(base);
  }
  if (!clean.length) return '붙임  (원문 첨부 확인) 1부.  끝.';
  if (clean.length === 1) return '붙임  ' + clean[0] + ' 1부.  끝.';
  const lines = [];
  for (let i = 0; i < clean.length; i++) {
    const num = i + 1;
    if (i === 0) lines.push('붙임  ' + num + '. ' + clean[i] + ' 1부.');
    else if (i === clean.length - 1) lines.push('      ' + num + '. ' + clean[i] + ' 1부.  끝.');
    else lines.push('      ' + num + '. ' + clean[i] + ' 1부.');
  }
  return lines.join('\n');
}

export function newSchoolNoticeDraft(title, body, attachmentNames) {
  let subject = (title || '').trim() || '안내';
  if (!/안내\s*$/.test(subject) && !/협조\s*$/.test(subject)) {
    subject = subject.replace(/\s*협조\s*$/, '').trim() + ' 안내';
  }
  const bodyStr = String(body || '');
  const issued = parseIssuedReference(bodyStr);
  const attachNames = [];
  for (const a of attachmentNames || []) {
    if (a) attachNames.push(String(a));
  }
  if (!attachNames.length) {
    for (const line of bodyStr.split(/\r?\n/)) {
      let am = line.match(/붙임\s*(?:\d+\s*[.:)]\s*)?(.+?)\s*1부/) || line.match(/\(붙임\s*\d*\)\s*(.+)$/);
      if (am) {
        const cand = am[1].trim();
        if (cand && !/원문 첨부/.test(cand)) attachNames.push(cand);
      }
    }
  }
  let purpose = '';
  for (const ln of bodyStr.split(/\r?\n/).map((x) => x.trim()).filter(Boolean)) {
    if (/^[12]\.\s*/.test(ln) && ln.length > 10 && !/관련|넘김/.test(ln)) {
      purpose = ln.replace(/^\d+\.\s*/, '');
      break;
    }
  }
  if (!purpose) purpose = '관련 공문에 따라 아래와 같이 안내하니 업무에 참고하시기 바랍니다.';

  const lines = [subject, ''];
  lines.push(issued.ok ? issued.value : '1. 관련: (원문 시행 부서·번호·날짜 확인)');
  lines.push('2. ' + purpose);
  lines.push('  가. 개요: (원문 표·핵심만 요약)');
  lines.push('  나. 기간: (원문 일정 확인)');
  lines.push('  다. 대상: (붙임 참고)');
  lines.push('  라. 행정사항; 기한 내 회신·제출 여부를 확인하시기 바랍니다.');
  lines.push('');
  lines.push(formatAttachEnding(attachNames));
  return lines.join('\n').replace(/\s+$/, '') + '\n';
}

/** Checklist for paste into 한글 기안 (cannot drive HWP from extension). */
export function hwpPasteChecklist() {
  return [
    '[한글 붙여넣기 체크리스트 — 확장은 HWP 창을 조작할 수 없음]',
    '1) 제목·본문 칸은 각각 따로 붙여넣기',
    '2) 「1. /가. 」 직후 내어쓰기: Alt+Tab (표 안은 Alt+Shift+Tab)',
    '3) (옵션) 5글자 이하 넘침 줄 → 단락 선택 후 Alt+Shift+J 후 Alt+Shift+N 반복(상한 6)',
    '4) (옵션) 본문 글자모양: 굴림 12pt (Alt+L)',
    '5) 줄간격·단락 스타일은 템플릿 유지',
    '6) 상신·발송·결재는 직접'
  ].join('\n');
}

/** Annotate numbered lines with outdent hint (for copy helpers). */
export function annotateOutdentLines(body) {
  return String(body || '')
    .split(/\r?\n/)
    .map((line) => {
      if (/^\s*(?:붙임\s+)?(?:\d+|[가-힣])\.\s+\S/.test(line)) {
        return line + '  «내어쓰기 Alt+Tab»';
      }
      return line;
    })
    .join('\n');
}

export function maskPersonalInfo(text) {
  const pairList = [];
  const counts = { name: 0, phone: 0, email: 0, rrn: 0, account: 0, addr: 0 };
  const labelMap = { name: '이름', phone: '전화', email: '이메일', rrn: '주민번호', account: '계좌', addr: '주소' };
  let work = String(text || '');

  function placeholder(value, kind) {
    if (!value) return value;
    for (const p of pairList) {
      if (p.Value === value) return p.Placeholder;
    }
    counts[kind] = (counts[kind] || 0) + 1;
    const ph = '[' + labelMap[kind] + String(counts[kind]) + ']';
    pairList.push({ Placeholder: ph, Value: value, Kind: kind });
    return ph;
  }

  const orgTokens = [];
  work = work.replace(/([가-힣]{2,20}(?:초등학교|중학교|고등학교|교육지원청|교육청|대학교|대학))/g, (v) => {
    let existing = orgTokens.find((o) => o.Value === v);
    if (!existing) {
      existing = { Token: '<<ORG' + (orgTokens.length + 1) + '>>', Value: v };
      orgTokens.push(existing);
    }
    return existing.Token;
  });
  for (const fixed of ['부산광역시교육청', '교육부', '한국기술교육대학교', '직업계고', '특성화고']) {
    if (work.indexOf(fixed) >= 0 && !orgTokens.find((o) => o.Value === fixed)) {
      const token = '<<ORG' + (orgTokens.length + 1) + '>>';
      orgTokens.push({ Token: token, Value: fixed });
      work = work.split(fixed).join(token);
    }
  }

  work = work.replace(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g, (v) => placeholder(v, 'email'));
  work = work.replace(/(?<!\d)\d{6}[-\s]?\d{7}(?!\d)/g, (v) => placeholder(v, 'rrn'));
  work = work.replace(/(?<!\d)(0\d{1,2}[-.\s]?\d{3,4}[-.\s]?\d{4})(?!\d)/g, (v) => placeholder(v, 'phone'));
  work = work.replace(/(?<!\d)(\d{2,6}[- ]\d{2,6}[- ]\d{2,6}(?:[- ]\d{2,6})?)(?!\d)/g, (v) => {
    const d = v.replace(/\D/g, '');
    if (d.length >= 10) return placeholder(v, 'account');
    return v;
  });
  work = work.replace(/((?:담당자|성명|작성자|기안자|처리자)\s*[:：]?\s*)([가-힣]{2,4})/g, (all, pre, nm) => {
    if (/학교|교육|부서|과장|장학|교사/.test(nm)) return all;
    return pre + placeholder(nm, 'name');
  });
  work = work.replace(/((?:주소|소재지)\s*[:：]\s*)([^\r\n]+)/g, (all, pre, rest) => pre + placeholder(rest.trim(), 'addr'));

  for (const o of orgTokens) {
    work = work.split(o.Token).join(o.Value);
  }
  return { Masked: work, Pairs: pairList };
}

export function unmaskPersonalInfo(text, pairs) {
  let r = String(text || '');
  const sorted = (pairs || []).slice().sort((a, b) => String(b.Placeholder || '').length - String(a.Placeholder || '').length);
  for (const p of sorted) {
    if (p && p.Placeholder) r = r.split(p.Placeholder).join(p.Value || '');
  }
  return r;
}

export function grokPrepPacket(title, body) {
  const raw = ((title || '') + '\n' + (body || '')).trim();
  const { Masked, Pairs } = maskPersonalInfo(raw);
  const packet = "안내공문으로 바꿔줘\n\n" + Masked;
  return { packet: packet, pairs: Pairs, masked: Masked };
}

export function tripDraftFromNotice(title, body) {
  let reason = String(title || '').trim() || '출장 참석';
  reason = reason.replace(/\s*신청\s*안내\s*$/, '').replace(/\s*안내\s*$/, '').replace(/\s*개최\s*$/, '').replace(/\s*협조\s*$/, '').trim();
  if (!/참석\s*$/.test(reason)) reason = reason + ' 참석';
  const text = (title + '\n' + body).replace(/\r/g, '');
  let place = '';
  for (const pat of [/장소\s*[:：]\s*([^\r\n]+)/, /일시\s*및\s*장소\s*[:：]\s*([^\r\n]+)/, /개최\s*장소\s*[:：]\s*([^\r\n]+)/, /위\s*치\s*[:：]\s*([^\r\n]+)/]) {
    const m = text.match(pat);
    if (m) { place = m[1].trim(); break; }
  }
  let dateText = '', timeText = '';
  let m = text.match(/(\d{4})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})\s*일?/);
  if (m) {
    dateText = m[1] + '-' + String(Number(m[2])).padStart(2, '0') + '-' + String(Number(m[3])).padStart(2, '0');
  }
  let m2 = text.match(/(\d{1,2})\s*:\s*(\d{2})\s*(?:~|-|–|—)\s*(\d{1,2})\s*:\s*(\d{2})/);
  if (m2) {
    timeText = String(Number(m2[1])).padStart(2, '0') + ':' + m2[2] + ' ~ ' + String(Number(m2[3])).padStart(2, '0') + ':' + m2[4];
  } else {
    const m3 = text.match(/(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분)?/);
    if (m3) {
      const mm = m3[2] ? Number(m3[2]) : 0;
      timeText = String(Number(m3[1])).padStart(2, '0') + ':' + String(mm).padStart(2, '0');
    }
  }
  const m4 = text.match(/(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.?(?:\([^)]*\))?\s*(\d{1,2})\s*:\s*(\d{2})/);
  if (m4) {
    if (!dateText) dateText = m4[1] + '-' + String(Number(m4[2])).padStart(2, '0') + '-' + String(Number(m4[3])).padStart(2, '0');
    if (!timeText) timeText = String(Number(m4[4])).padStart(2, '0') + ':' + m4[5];
  }
  const region = /부산/.test(place + ' ' + text) ? '관내' : '관외';
  const copyText = [
    '출장사유: ' + reason,
    '구분: ' + region,
    '날짜: ' + (dateText || '(원문 확인)'),
    '시간: ' + (timeText || '(원문 확인)'),
    '장소: ' + (place || '(원문 확인)')
  ].join('\n');
  return {
    purpose: reason,
    place: place,
    start: dateText,
    end: dateText,
    region: region,
    time: timeText,
    CopyText: copyText
  };
}

export function dueDateFromText(text) {
  if (!text) return null;
  const now = new Date();
  const y = now.getFullYear();
  const pad = (n) => String(n).padStart(2, '0');
  const ymd = (dt) => dt.getFullYear() + '-' + pad(dt.getMonth() + 1) + '-' + pad(dt.getDate());
  if (/오늘/.test(text)) return ymd(now);
  if (/내일/.test(text)) { const d = new Date(now); d.setDate(d.getDate() + 1); return ymd(d); }
  if (/모레/.test(text)) { const d = new Date(now); d.setDate(d.getDate() + 2); return ymd(d); }
  let m = text.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/);
  if (m) {
    const dt = new Date(y, Number(m[1]) - 1, Number(m[2]));
    if (dt.getTime() < now.getTime() - 30 * 86400000) dt.setFullYear(y + 1);
    return ymd(dt);
  }
  m = text.match(/(?<!\d)(\d{1,2})[./\-](\d{1,2})(?:[./\-](\d{2,4}))?(?!\d)/);
  if (m) {
    let yy = y;
    if (m[3]) {
      const yp = Number(m[3]);
      yy = yp < 100 ? 2000 + yp : yp;
    }
    const dt = new Date(yy, Number(m[1]) - 1, Number(m[2]));
    if (!m[3] && dt.getTime() < now.getTime() - 30 * 86400000) dt.setFullYear(y + 1);
    return ymd(dt);
  }
  m = text.match(/(\d{4})[.\-/년]\s*(\d{1,2})[.\-/월]\s*(\d{1,2})/);
  if (m) return m[1] + '-' + pad(Number(m[2])) + '-' + pad(Number(m[3]));
  return null;
}
