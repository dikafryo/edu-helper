import { buildDutyData, localDate } from './duty.js';
import { prepareRoute } from './neis-route.js';
const $ = id => document.getElementById(id);
let selection = null;
let running = false;
let trigger = null;
async function showLastRun() {
  const {neisLastRun:r} = await chrome.storage.session.get('neisLastRun');
  if (r) $('neisLastRun').textContent = `최근 자동 신청 · ${r.running ? '진행 중 (오래 유지되면 나이스 화면 확인)' : r.ok ? '완료' : '중단'} · ${r.step || ''} ${r.message || r.error || ''}`;
}
void showLastRun();
chrome.storage.onChanged.addListener((changes, area) => { if(area==='session' && changes.neisLastRun) void showLastRun(); });
$('dutyAuto').addEventListener('click', async () => {
  if(!selection || running) return;
  try {
    const overrides={start:$('dutyStart').value,end:$('dutyEnd').value,time:$('dutyTime').value,reason:$('dutyReason').value};
    prepareRoute(selection.preset,overrides);
    running=true; $('dutyAuto').disabled=true; $('dutyApply').disabled=true; $('dutyCancel').disabled=true;
    $('dutyPreviewStatus').textContent='나이스 자동 신청 시작 · 팝업이 닫혀도 실행 결과는 다시 열어 확인할 수 있습니다.';
    const result=await chrome.runtime.sendMessage({type:'NEIS_AUTO_ROUTE',index:selection.index,expectedPreset:selection.preset,overrides});
    $('dutyPreviewStatus').textContent=result?.message || result?.error || '실행 결과를 확인하세요.';
  } catch(e){$('dutyPreviewStatus').textContent=e.message;}
  finally{running=false;$('dutyAuto').disabled=false;$('dutyApply').disabled=false;$('dutyCancel').disabled=false;}
});

export function showDutyPreview(preset, index, source) {
  if (running) return;
  selection = { preset: { ...preset }, index };
  trigger = source;
  $('dutyPreviewTitle').textContent = `${preset.Label || preset.Key} · 실행 전 확인`;
  $('dutyStart').value = localDate();
  $('dutyEnd').value = localDate();
  $('dutyEnd').min = $('dutyStart').value;
  $('dutyTime').value = preset.Time || '';
  $('dutyReason').value = preset.Reason || '';
  $('dutyPreviewStatus').textContent = '이번 실행에만 적용됩니다. 저장된 루틴은 바뀌지 않습니다.';
  $('dutyPreview').hidden = false;
  $('dutyStart').focus();
}

$('dutyCancel').addEventListener('click', () => {
  if (running) return;
  selection = null;
  $('dutyPreview').hidden = true;
  trigger?.focus();
});
$('dutyStart').addEventListener('change', () => {
  if ($('dutyEnd').value < $('dutyStart').value) $('dutyEnd').value = $('dutyStart').value;
  $('dutyEnd').min = $('dutyStart').value;
});
$('dutyApply').addEventListener('click', async () => {
  if (!selection || running) return;
  try {
    const overrides = { start: $('dutyStart').value, end: $('dutyEnd').value, time: $('dutyTime').value, reason: $('dutyReason').value };
    buildDutyData(selection.preset, overrides);
    running = true;
    $('dutyApply').disabled = true;
    $('dutyCancel').disabled = true;
    $('dutyPreviewStatus').textContent = '복무 화면에 입력 중…';
    const result = await chrome.runtime.sendMessage({ type: 'APPLY_DUTY_PRESET', index: selection.index, expectedPreset: selection.preset, overrides });
    $('dutyPreviewStatus').textContent = result?.ok
      ? `${result.filled}개 항목에 입력했습니다. 나이스에서 날짜·시간·사유를 확인하세요. 상신은 직접 해주세요.`
      : result?.error || '응답이 없습니다. 확장 프로그램을 새로고침하고 다시 시도하세요.';
  } catch (error) {
    $('dutyPreviewStatus').textContent = error.message || '입력 실패';
  } finally {
    running = false;
    $('dutyApply').disabled = false;
    $('dutyCancel').disabled = false;
  }
});
