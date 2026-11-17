// PIN applies to opening the popup/dock as well as session expiry.
const content = document.createElement('div');
content.className = 'app-content';
while (document.body.firstChild) content.appendChild(document.body.firstChild);
document.body.appendChild(content);
const gate = document.createElement('section');
gate.className = 'start-lock';
gate.innerHTML = '<h2>교직원 업무도우미 잠금</h2><p>PIN을 입력하고 잠금 해제 시간을 선택하세요.</p><form><label>PIN<input type="password" inputmode="numeric" autocomplete="off" maxlength="12" required aria-label="잠금 해제 PIN"></label><label>잠금 해제 유지<select aria-label="잠금 해제 유지 시간"><option value="21600000">6시간</option><option value="86400000">하루 (24시간)</option></select></label><p>브라우저 종료·Windows 잠금·직접 잠금 시 종료됩니다.</p><button type="submit">잠금 해제</button></form><p role="status"></p><a href="options.html#security" target="_blank">처음 사용 · PIN 설정 ↗</a>';
document.body.appendChild(gate);
const input = gate.querySelector('input');
const status = gate.querySelector('[role=status]');
let pending = false;
let refreshVersion = 0;
function locked(on) { content.hidden = on; content.inert = on; gate.hidden = !on; }
locked(true);
async function refresh() {
  const version=++refreshVersion;
  try {
    const state = await chrome.runtime.sendMessage({ type: 'VAULT_STATUS' });
    if(version!==refreshVersion)return;
    if (!state?.ok) throw new Error('잠금 상태를 확인하지 못했습니다. 다시 열어주세요.');
    // PIN 잠금을 쓰지 않는 경우(첫 실행 기본값)에는 잠금 화면 없이 바로 사용한다.
    locked(!!state.pinLockEnabled && !state.unlocked);
  } catch (e) { if(version!==refreshVersion)return;locked(true); status.textContent = e.message; }
}
gate.querySelector('form').addEventListener('submit', async event => {
  event.preventDefault(); if (pending) return; pending = true;refreshVersion++;
  const submit=gate.querySelector('button[type=submit]');submit.disabled=true;status.textContent='PIN 확인 중…';
  const pin = input.value; input.value = '';
  try {
    const result = await chrome.runtime.sendMessage({ type: 'PIN_UNLOCK', pin, unlockMs: Number(gate.querySelector('select').value) });
    if (!result?.ok || !result.unlocked) throw new Error(result?.error || 'PIN 확인 실패');
    refreshVersion++;status.textContent = '';locked(false);
  } catch (e) { status.textContent = e.message; }
  finally { pending = false;submit.disabled=false; }
});
void refresh();
setInterval(() => { if (!pending) void refresh(); }, 5000);
