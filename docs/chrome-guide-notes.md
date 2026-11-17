# Chrome Modern Web Guidance — pen도우미 적용 메모

- **MV3 + least privilege**: `host_permissions` / content_scripts만 업무포털·에듀파인·나이스 스코프. CSP `script-src 'self'` (인라인 없음).
- **UI**: 와이드 sidePanel 대신 **우측(~52px) 세로 레일** content script. 접기 탭·Y축 드래그·`chrome.storage.local` 상태. 기본 `data-side=right`.
- **단축키**: `commands.toggle-rail` = **Alt+Shift+D** (+ content `e.code==='KeyD'` IME 폴백). `chrome://extensions/shortcuts`에서 재확인.
- **SW lifecycle**: alarms로 세션 핑; 무거운 작업은 메시지 브리지. 온디바이스 Summarizer/LanguageModel은 feature-detect 후 fallback.
- **안전**: fill-only(상신/저장/결재/접수/확인 클릭 금지). 외부 네트워크 없음. 개인용 unpacked.

## Alt+Shift+D 충돌 점검 (2026-11-01 Asia/Seoul)

- Chrome `extensions.commands`: **Alt+Shift+D → pen도우미(toggle-rail)만** 점유. 다른 확장과 충돌 없음.
- 웹한글기안기/포털 페이지 내장 단축키는 Chrome commands와 별개(페이지 keydown). 레일은 `Alt+Shift+KeyD`에서 `preventDefault`하되 입력 필드 포커스 시 패스하는 폴백 로직 권장 — 기안기 편집 중 가로채기 최소화.