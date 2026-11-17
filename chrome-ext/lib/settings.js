// Validate the complete draft before writing any settings.
const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function validateSettings(value) {
  if (!isRecord(value)) throw new Error('설정은 객체여야 합니다.');
  if (!Array.isArray(value.taskCards) || !value.taskCards.every(isRecord)) {
    throw new Error('과제카드는 객체 목록([])이어야 합니다.');
  }
  for (const key of ['travelForm', 'dutyForm']) {
    if (!isRecord(value[key])) throw new Error(`${key}은 객체({})여야 합니다.`);
  }
  validateDutyPresets(value.dutyPresets);
  return value;
}

export function validateDutyPresets(presets) {
  if (!Array.isArray(presets)) throw new Error('복무 루틴은 목록([])이어야 합니다.');
  presets.forEach((preset, index) => {
    const label = `복무 루틴 ${index + 1}번`;
    if (!isRecord(preset)) throw new Error(`${label}: 객체여야 합니다.`);
    for (const key of ['Key', 'Label', 'Reason', 'Time', 'Url']) {
      if (preset[key] !== undefined && typeof preset[key] !== 'string') {
        throw new Error(`${label}: ${key}은 문자열이어야 합니다.`);
      }
    }
    if (!(preset.Label || preset.Key || '').trim()) throw new Error(`${label}: 버튼 이름을 입력하세요.`);
    if (preset.Url) {
      let url;
      try { url = new URL(preset.Url); } catch { throw new Error(`${label}: 주소를 확인하세요.`); }
      if (url.protocol !== 'https:' || url.username || url.password) {
        throw new Error(`${label}: 사용자 정보 없는 HTTPS 주소를 입력하세요.`);
      }
    }
  });
  return presets;
}
