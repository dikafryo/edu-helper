// Executed in the page's MAIN world. Each request advances at most one step.
export function inspectWorkflow(action, execute = false, expected = '') {
  const visible = el => !!el && !!el.getClientRects().length;
  const apps = window.cpr?.core?.Platform?.INSTANCE?.getAllRunningAppInstances?.() || [];
  const find = id => apps.find(a => a.app?.id === id);
  let control = null;
  let step = '';
  if (action === 'neis') {
    const line = find('edu/cm/wam/woa/pm/wam_woapm07_p02');
    if (line) return { ok: false, error: '개인결재선 창이 열려 있습니다. 원하는 결재선을 선택하고 [지정]을 눌러주세요.' };
    const draft = find('edu/cm/wam/woa/pm/wam_woapm07_p00');
    if (draft) { control = draft.lookup('btnSelectMySancr'); step = '개인결재선 열기'; }
    else {
      const forms = ['srv_mymmm00_p00', 'srv_mymmm02_p00', 'srv_mymmm03_p00']
        .map(id => find('edu/ga/srv/mym/mm/' + id)).filter(Boolean);
      if (forms.length !== 1) return { ok: false, error: '복무 신청 창 한 개를 열고 입력 내용을 확인하세요.' };
      control = forms[0].lookup('btnAprvDmnd');
      step = '승인요청 창 열기';
    }
    if (!control || control.enabled === false || control.visible === false) return { ok: false, error: '현재 단계의 버튼이 비활성 상태입니다. 필수 항목을 확인하세요.' };
  } else {
    const labels = action === 'approval' ? ['결재대기', '결재 대기'] : ['다음', '다음 단계'];
    const matches = [...document.querySelectorAll('button,a,input[type=button],[role=button]')]
      .filter(visible).filter(el => !el.disabled && el.getAttribute('aria-disabled') !== 'true')
      .filter(el => labels.includes((el.innerText || el.value || el.getAttribute('aria-label') || '').trim()));
    if (matches.length !== 1) return { ok: false, error: matches.length ? '같은 이름의 버튼이 여러 개입니다. 업무 화면에서 직접 선택하세요.' : '이 화면에서 다음 단계 버튼을 찾지 못했습니다. 로그인 상태와 기안 화면을 확인하세요.' };
    control = matches[0];
    step = action === 'approval' ? '결재대기 메뉴 열기' : '기안 다음 단계 열기';
  }
  if (!execute) return { ok: true, step };
  if (expected !== step) return { ok: false, error: '화면 단계가 변경되었습니다. 다시 확인하세요.' };
  control.click();
  return { ok: true, step, message: `${step}를 요청했습니다. 업무 화면의 오류·필수 항목 안내를 확인하세요. 상신은 실행하지 않았습니다.` };
}

export async function workflowStep(action, execute, expected, target) {
  if (!['neis', 'approval', 'draft'].includes(action)) return { ok: false, error: '지원하지 않는 단계입니다.' };
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!tab?.id) return { ok: false, error: '업무 탭을 먼저 선택하세요.' };
  const host = new URL(tab.url || 'about:blank').hostname;
  if (!(action === 'neis' ? /(^|\.)neis\.go\.kr$/ : /(^|\.)pen\.go\.kr$/).test(host)) {
    return { ok: false, error: action === 'neis' ? '로그인한 나이스 업무 탭에서 실행하세요.' : '부산 에듀파인 업무 탭에서 실행하세요.' };
  }
  if (execute) {
    if (target?.tabId !== tab.id || !Number.isInteger(target.frameId)) return { ok: false, error: '대상 탭이 변경되었습니다. 다시 확인하세요.' };
    const result = await chrome.scripting.executeScript({ target: { tabId: tab.id, frameIds: [target.frameId] }, world: 'MAIN', func: inspectWorkflow, args: [action, true, expected] });
    return result[0]?.result || { ok: false, error: '화면 응답이 없습니다.' };
  }
  const results = await chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, world: 'MAIN', func: inspectWorkflow, args: [action, false] });
  const matches = results.filter(r => r.result?.ok);
  if (matches.length !== 1) return { ok: false, error: matches.length ? '여러 업무 프레임에서 버튼을 찾았습니다. 해당 화면에서 직접 진행하세요.' : results.find(r => r.result?.error)?.result.error || '업무 화면을 찾지 못했습니다.' };
  return { ...matches[0].result, target: { tabId: tab.id, frameId: matches[0].frameId } };
}
