# Chrome extension load status (Asia/Seoul 2026-11-01)

## Cause of 1.2.3 + 오류
- Chrome **km79 (Default)** profile loads unpacked from:
  `F:\claude\01 개발 프로그램\pen도우미\chrome-ext`
- UI showed 1.2.3 / 오류 because the **card was not reloaded** after fixes; error text was:
  `Uncaught SyntaxError: Unexpected token '||'` in `rail.js` (nullish `??` mixed with `||`).
- Stale error badge can remain until **오류 → 모두 삭제** and **새로고침**.

## Fixed on disk now
- Version **1.2.8** (manifest + rail banner). Confirmed on chrome://extensions after 새로고침: **1.2.8**, no 오류 button.
- All JS: `node --check` OK; no `??` in chrome-ext.

## What user must click
1. Open Chrome profile **km79** (not profile picker only).
2. `chrome://extensions`
3. On pen도우미 card click **새로고침** (circular arrows). Should show **1.2.8**.
4. If 오류 still visible: open **오류** → **모두 삭제** → **새로고침** again.
5. Refresh portal/에듀파인 tabs so content script reinjects.
6. Only if version still stuck: **삭제** then **압축을 푼 확장 프로그램 로드** → same folder above.