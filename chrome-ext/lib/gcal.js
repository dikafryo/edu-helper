/** Google Calendar TEMPLATE URL helper. No OAuth / no API. */

import { maskPersonalInfo } from './notice.js';

export function maskGCalText(text) {
  if (!text) return '';
  try {
    const r = maskPersonalInfo(String(text));
    return (r && r.Masked) ? r.Masked : String(text);
  } catch (_) {
    return String(text);
  }
}

export function newGCalTemplateUrl(title, dateYmd, details) {
  let d;
  try {
    const parts = String(dateYmd || '').split('-').map(Number);
    if (parts.length === 3 && parts[0] && parts[1] && parts[2]) {
      d = new Date(parts[0], parts[1] - 1, parts[2]);
    } else d = new Date();
  } catch (_) {
    d = new Date();
  }
  const pad = (n) => String(n).padStart(2, '0');
  const start = d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate());
  const endD = new Date(d.getTime());
  endD.setDate(endD.getDate() + 1);
  const end = endD.getFullYear() + pad(endD.getMonth() + 1) + pad(endD.getDate());
  const t = encodeURIComponent(maskGCalText(title || '일정'));
  const det = encodeURIComponent(maskGCalText(details || ''));
  return 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=' + t + '&dates=' + start + '/' + end + '&details=' + det;
}
