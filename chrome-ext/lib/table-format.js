export function parseTableText(text) {
  const lines = String(text || '').replace(/\r\n?/g, '\n').trim().split('\n');
  if (!lines[0]) throw new Error('표 내용을 먼저 입력하세요.');
  let rows;
  if (lines.some(line => line.includes('\t'))) rows = lines.map(line => line.split('\t'));
  else if (lines.every(line => line.includes('|'))) {
    rows = lines.map(line => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(cell => cell.trim()))
      .filter(row => !row.every(cell => /^:?-{3,}:?$/.test(cell)));
  } else throw new Error('탭으로 구분한 표 또는 |로 구분한 표를 입력하세요.');
  const width = Math.max(...rows.map(row => row.length));
  if (rows.length > 200 || width > 30) throw new Error('표는 200행·30열 이내로 나눠주세요.');
  return rows.map(row => Array.from({ length: width }, (_, i) => row[i] || ''));
}

export function escapeCell(text) {
  return String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])).replace(/\r\n?|\n/g, '<br>');
}

export function tableClipboard(rows) {
  const html = '<html><head><meta charset="utf-8"></head><body><!--StartFragment--><table border="1" cellspacing="0" cellpadding="6" style="border-collapse:collapse;border:1px solid #000;font-family:굴림,Malgun Gothic,sans-serif;font-size:12pt;">' + rows.map(row => '<tr>' + row.map(cell => {
    const span = (key, value) => Number.isInteger(value) && value > 1 && value <= 200 ? ` ${key}="${value}"` : '';
    return '<td' + span('rowspan', cell.rowSpan) + span('colspan', cell.colSpan) + ' style="border:1px solid #000;padding:6px;vertical-align:middle;white-space:pre-wrap;">' + escapeCell(cell.text) + '</td>';
  }).join('') + '</tr>').join('') + '</table><!--EndFragment--></body></html>';
  return { html, text: rows.map(row => row.map(cell => cell.text).join('\t')).join('\r\n') };
}
