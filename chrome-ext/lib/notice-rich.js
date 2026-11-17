import { newSchoolNoticeDraft } from './notice.js';
import { tableClipboard, escapeCell } from './table-format.js';

export function noticeWithTables(title, body, tables = [], attachments = []) {
  if (tables.length > 20) throw new Error('표가 너무 많습니다. 공문 본문만 선택해 다시 읽어주세요.');
  const draft = newSchoolNoticeDraft(title, body, attachments);
  const marker = '  가. 개요: (원문 표·핵심만 요약)';
  const tableParts = tables.map(rows => {
    if (!Array.isArray(rows) || rows.length > 200 || rows.some(row => !Array.isArray(row) || row.length > 30)) throw new Error('표 크기를 확인하세요.');
    return tableClipboard(rows);
  });
  const [before, after = ''] = draft.split(marker);
  const paragraphs = text => text.split('\n').map(line => `<p style="margin:0 0 6pt;white-space:pre-wrap;">${escapeCell(line) || '<br>'}</p>`).join('');
  const fragments = tableParts.map(part => part.html.split('<!--StartFragment-->')[1].split('<!--EndFragment-->')[0]).join('<p><br></p>');
  const html = tableParts.length ? paragraphs(before + '  가. 개요:') + fragments + paragraphs(after) : paragraphs(draft);
  const text = tableParts.length ? before + '  가. 개요:\n' + tableParts.map(part => part.text).join('\n\n') + after : draft;
  return { html, text, count: tables.length };
}

export function readSourceHtml(html) {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll('script,style,iframe,img,object').forEach(el => el.remove());
  const tables = [...doc.querySelectorAll('table')].filter(t => !t.parentElement.closest('table')).map(table => [...table.rows].map(row => [...row.cells].map(cell => {
    const clone = cell.cloneNode(true);
    clone.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
    return { text: clone.textContent || '', rowSpan: cell.rowSpan, colSpan: cell.colSpan };
  })));
  doc.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
  doc.querySelectorAll('td,th').forEach(el => el.append('\t'));
  doc.querySelectorAll('p,div,tr').forEach(el => el.append('\n'));
  return { body: doc.body.textContent || '', tables };
}

export async function copyNotice(html, text) {
  if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') throw new Error('서식 복사를 지원하지 않는 환경입니다.');
  await navigator.clipboard.write([new ClipboardItem({
    'text/html': new Blob(['<html><head><meta charset="utf-8"></head><body><!--StartFragment-->' + html + '<!--EndFragment--></body></html>'], {type:'text/html'}),
    'text/plain': new Blob([text], {type:'text/plain'})
  })]);
}
