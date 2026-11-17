export function localDate() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(value + 'T12:00:00Z');
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function buildDutyData(preset, overrides = {}) {
  if (!preset || typeof overrides !== 'object' || overrides === null || Array.isArray(overrides)) throw new Error('복무 루틴을 다시 선택하세요.');
  const start = overrides.start ?? localDate();
  const end = overrides.end ?? start;
  if (!validDate(start) || !validDate(end)) throw new Error('시작일과 종료일을 올바르게 입력하세요.');
  if (end < start) throw new Error('종료일은 시작일보다 빠를 수 없습니다.');
  const time = overrides.time ?? preset.Time ?? '';
  const reason = overrides.reason ?? preset.Reason ?? '';
  if (typeof time !== 'string' || typeof reason !== 'string') throw new Error('시간과 사유를 확인하세요.');
  const type = preset.Label || preset.Key || '';
  if (!type.trim()) throw new Error('복무 종류를 설정하세요.');
  return { type, start, end, time: time.trim(), reason: reason.trim() };
}
