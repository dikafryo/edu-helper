import { parseTableText, tableClipboard } from './table-format.js';
const $ = id => document.getElementById(id);
const editor = $('tableEditor');
const status = $('tableStatus');
function rowsFrom(table) {
  const rows = [...table.rows];
  if (rows.length > 200 || rows.some(row => row.cells.length > 30)) throw new Error('표는 200행·30열 이내로 나눠주세요.');
  return rows.map(row => [...row.cells].map(cell => {
    const copy = cell.cloneNode(true);
    copy.querySelectorAll('script,style').forEach(node => node.remove());
    copy.querySelectorAll('br').forEach(node => node.replaceWith('\n'));
    return { text: cell.isConnected ? cell.innerText : copy.textContent || '', rowSpan: cell.rowSpan, colSpan: cell.colSpan };
  }));
}
function render(rows) {
  const table = document.createElement('table');
  for (const row of rows) {
    const tr = table.insertRow();
    for (const value of row) {
      const cell = tr.insertCell(); cell.textContent = value.text;
      cell.rowSpan = Math.max(1, Math.min(200, value.rowSpan || 1));
      cell.colSpan = Math.max(1, Math.min(30, value.colSpan || 1));
      cell.contentEditable = 'true'; cell.setAttribute('aria-label', '표 셀 편집');
    }
  }
  editor.replaceChildren(table);
  status.textContent = '셀을 눌러 수정한 뒤 표 그대로 복사를 누르세요.';
}
$('btnTableOpen').addEventListener('click', () => {
  $('resultPanel').hidden = false; $('tablePanel').hidden = false;
  $('tableSource').focus();
});
$('tableConvert').addEventListener('click', () => {
  try { render(parseTableText($('tableSource').value).map(row => row.map(text => ({ text })))); }
  catch (e) { status.textContent = e.message; }
});
$('tableNew').addEventListener('click', () => render(Array.from({length:3}, () => Array.from({length:3}, () => ({text:''})))));
function pasteTable(event) {
  try {
    const html = event.clipboardData?.getData('text/html');
    const table = html && new DOMParser().parseFromString(html, 'text/html').querySelector('table');
    if (table) { event.preventDefault(); render(rowsFrom(table)); return; }
    if (event.target.closest('td')) { event.preventDefault();
      // Keep pasted content as text; never insert arbitrary clipboard HTML.
      const selection = window.getSelection();
      if (selection?.rangeCount) { const range = selection.getRangeAt(0); range.deleteContents(); const text = document.createTextNode(event.clipboardData.getData('text/plain')); range.insertNode(text); range.setStartAfter(text); range.collapse(true); selection.removeAllRanges(); selection.addRange(range); }
    }
  } catch(e) { event.preventDefault(); status.textContent = e.message; }
}
$('tableSource').addEventListener('paste', pasteTable);
editor.addEventListener('paste', pasteTable);
$('tableCopy').addEventListener('click', async () => {
  try {
    const table = editor.querySelector('table');
    if (!table) throw new Error('표를 만들거나 붙여넣으세요.');
    const payload = tableClipboard(rowsFrom(table));
    if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') throw new Error('이 환경에서 표 복사를 지원하지 않습니다.');
    await navigator.clipboard.write([new ClipboardItem({ 'text/html': new Blob([payload.html], {type:'text/html'}), 'text/plain': new Blob([payload.text], {type:'text/plain'}) })]);
    status.textContent = '표 형식으로 복사했습니다. 공문 본문에서 Ctrl+V로 붙여넣으세요. 텍스트 전용 붙여넣기는 표를 제거합니다.';
  } catch(e) { status.textContent = '표 복사 실패: ' + e.message; }
});
