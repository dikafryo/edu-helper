const status = document.getElementById('workflowStatus');
const run = document.getElementById('workflowRun');
let pending = null;
let busy = false;
document.querySelectorAll('[data-workflow]').forEach(button => button.addEventListener('click', async () => {
  if (busy) return;
  busy = true; pending = null; run.hidden = true;
  status.textContent = '현재 화면 확인 중…';
  try {
    const action = button.dataset.workflow;
    const result = await chrome.runtime.sendMessage({ type: 'WORKFLOW_STEP', action });
    if (!result?.ok) throw new Error(result?.error || '화면 확인 실패');
    pending = { action, expected: result.step, target: result.target };
    status.textContent = `${result.step} 단계입니다. 입력 내용을 확인한 뒤 아래 버튼으로 진행하세요. 승인요청 시 임시저장될 수 있습니다.`;
    run.textContent = result.step;
    run.hidden = false;
  } catch (error) { status.textContent = error.message; }
  finally { busy = false; }
}));
run.addEventListener('click', async () => {
  if (!pending || busy) return;
  busy = true; run.disabled = true;
  try {
    const result = await chrome.runtime.sendMessage({ type: 'WORKFLOW_STEP', execute: true, ...pending });
    status.textContent = result?.message || result?.error || '응답이 없습니다. 업무 화면을 확인하세요.';
  } catch (error) { status.textContent = error.message; }
  finally { busy = false; pending = null; run.disabled = false; run.hidden = true; }
});
