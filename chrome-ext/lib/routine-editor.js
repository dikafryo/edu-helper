import { validateDutyPresets } from './settings.js';
const $ = id => document.getElementById(id);
let draft = [];

export function renderRoutines(presets) {
  draft = presets.map(p => ({ ...p }));
  $('routineList').replaceChildren();
  draft.forEach((preset, index) => {
    const group = document.createElement('fieldset');
    group.className = 'routine';
    const legend = document.createElement('legend');
    legend.textContent = `루틴 ${index + 1}${index === 0 ? ' · 단축키 대상' : ''}`;
    group.appendChild(legend);
    for (const [key, title, hint] of [
      ['Label', '복무 종류 · 버튼 이름', '예: 시간외 / 연가 / 조퇴 / 외출'],
      ['Time', '시간', '예: 18:00~20:00 / 16:00 / 종일'],
      ['Reason', '사유', '예: 수업 준비'],
      ['LineName', '자동 신청 · 개인결재선 이름', '나이스에 저장된 이름과 동일하게'],
      ['LeaveReason', '연가 사유 코드 (연가만)', '00~09 · 나이스 연가 사유 확인'],
      ['Place', '출장지 (출장만)', '출장 장소'],
      ['Contact', '연락처 (출장 필수)', '010-0000-0000'],
      ['TripType', '출장 구분 코드 (출장만)', '10 관내 / 20 관외 / 30 국외 / 40 연수']
    ]) {
      const label = document.createElement('label');
      label.textContent = title;
      const input = document.createElement('input');
      input.type = 'text';
      input.value = preset[key] || (key === 'Label' ? preset.Key || '' : '');
      preset[key] = input.value;
      input.placeholder = hint;
      input.addEventListener('input', () => {
        preset[key] = input.value;
        $('routineStatus').textContent = '변경한 내용을 저장해주세요.';
      });
      label.appendChild(input);
      group.appendChild(label);
    }
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'remove';
    remove.textContent = '이 루틴 삭제';
    remove.addEventListener('click', () => {
      renderRoutines(draft.filter((_, i) => i !== index));
      $('routineStatus').textContent = '삭제를 반영하려면 저장해주세요.';
    });
    group.appendChild(remove);
    $('routineList').appendChild(group);
  });
}

$('addRoutine').addEventListener('click', () => {
  renderRoutines([...draft, { Label: '', Reason: '', Time: '', Url: '' }]);
  $('routineList').lastElementChild.querySelector('input').focus();
  $('routineStatus').textContent = '새 루틴을 입력하고 저장해주세요.';
});

$('saveRoutines').addEventListener('click', async () => {
  try {
    const presets = validateDutyPresets(draft.map(p => ({ ...p })));
    await chrome.storage.local.set({ dutyPresets: presets, dutyPresetsSeeded: true });
    $('presets').value = JSON.stringify(presets, null, 2);
    $('routineStatus').textContent = `${presets.length}개 루틴 저장됨 · 팝업을 다시 열면 반영됩니다.`;
  } catch (error) {
    $('routineStatus').textContent = error.message || '루틴 저장 실패';
  }
});
