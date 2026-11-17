export function openApplication(kind, send, readPage, report) {
  document.getElementById('applicationForm')?.remove();
  const panel = document.createElement('section'); panel.id = 'applicationForm'; panel.className = 'application-form';
  const title = document.createElement('h3'); title.textContent = kind === 'travel' ? '출장신청' : '복무신청'; panel.appendChild(title);
  const fields = {};
  const definitions = kind === 'travel' ? [['purpose','출장 목적'],['place','출장지'],['start','시작일'],['end','종료일'],['time','시간'],['region','출장 구분']] : [['type','복무 종류'],['start','시작일'],['end','종료일'],['time','시간'],['reason','사유']];
  for (const [key, name] of definitions) {
    const label = document.createElement('label'); label.textContent = name;
    const field = document.createElement(key === 'type' ? 'select' : 'input');
    if (key === 'type') for (const value of ['시간외근무','연가','조퇴','외출','지각','병가','병조퇴']) { const option = document.createElement('option'); option.value = option.textContent = value; field.appendChild(option); }
    else field.type = ['start','end'].includes(key) ? 'date' : 'text';
    fields[key] = field; label.appendChild(field); panel.appendChild(label);
  }
  const note = document.createElement('p'); note.textContent = '신청 화면을 직접 연 뒤 내용을 확인하고 채우세요. 기존 값이 바뀔 수 있습니다. 상신은 직접 합니다.'; panel.appendChild(note);
  let busy = false;
  const storageKey = kind === 'travel' ? 'travelForm' : 'dutyForm';
  let edited = false;
  let writes = Promise.resolve();
  function saveDraft() {
    edited = true;
    const data = Object.fromEntries(Object.entries(fields).map(([key, field]) => [key, field.value]));
    writes = writes.catch(() => {}).then(() => chrome.storage.local.set({ [storageKey]: data })).catch(() => { note.textContent = '임시 내용 저장 실패 · 창을 닫기 전에 다시 확인하세요.'; });
  }
  for (const field of Object.values(fields)) field.addEventListener('input', saveDraft);
  chrome.storage.local.get(storageKey).then(result => {
    if (edited) return;
    for (const [key, field] of Object.entries(fields)) if (result[storageKey]?.[key]) field.value = result[storageKey][key];
  }).catch(() => { note.textContent = '이전 내용을 불러오지 못했습니다. 직접 입력하세요.'; });
  function button(text, action) { const b = document.createElement('button'); b.type = 'button'; b.textContent = text; b.addEventListener('click', async () => { if (busy) return; busy = true; b.disabled = true; try { await action(); } catch(e) { note.textContent = e.message; } finally { busy = false; b.disabled = false; } }); panel.appendChild(b); }
  if (kind === 'travel') button('현재 원문에서 추출', async () => {
    const page = await readPage();
    const r = await chrome.runtime.sendMessage({ type:'TRIP_DRAFT', title:page.title || '', body:page.body || '' });
    if (!r?.ok || !r.draft) throw new Error(r?.error || '출장 정보 추출 실패');
    for (const key of Object.keys(fields)) fields[key].value = r.draft[key] || '';
    saveDraft();
    note.textContent = '추출 내용을 확인·수정하세요. 출장 신청 화면으로 이동한 뒤 채우기를 누르세요.';
  });
  button('확인한 내용 채우기', async () => {
    const data = Object.fromEntries(Object.entries(fields).map(([key, field]) => [key, field.value.trim()]));
    if (!data.start || !data.end || data.end < data.start) throw new Error('시작일·종료일을 확인하세요.');
    if (!(data.purpose || data.reason)) throw new Error('목적 또는 사유를 입력하세요.');
    const r = await send({ type:kind === 'travel' ? 'FILL_TRAVEL' : 'FILL_DUTY', data });
    if (!r?.ok || !r.filled) throw new Error(r?.error || '입력한 칸이 없습니다. 신청 화면을 확인하세요.');
    note.textContent = `${r.filled}개 항목 입력. 업무 화면에서 결과를 확인하세요.`; report(note.textContent);
  });
  button('닫기', async () => panel.remove());
  const host = document.getElementById('actions') || document.querySelector('.pad'); host.after(panel);
  fields[Object.keys(fields)[0]].focus();
}
