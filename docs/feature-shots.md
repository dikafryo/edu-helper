# pen도우미 기능 샷 목록 (Asia/Seoul 2026-11-01)

개인정보 하단 상태줄 마스킹. 상신/저장/결재/접수/확인 자동 클릭 없음(fill-only).

## 오류 원인 / 수정
1. **확장 rail.js SyntaxError `??`+`||`**: 괄호 없는 혼용 → Unexpected token `||`. 이후 `] catch` 오타도 관측. **최종: `??` 제거(삼항으로 치환), try/catch 정상, v1.2.6**. `node --check` 전부 OK. Chrome 156.
2. **standalone 메신저 감시 오류**: UTF-8 무BOM → PS5.1 CP949 오판으로 PenExtras 로드 실패 → `$script:KeepAliveTick` StrictMode 미초기화. **UTF-8 BOM + Tick=0 + Get-Variable 가드**.
3. **안내공문 `$Settings`/`$HostPanel`**: 헤더 `?#` 깨짐 + Settings guard가 `param` 앞. **헤더 복구, Settings 강제 로드, guard를 param 뒤**.

## Edge (스토어 없음)
- HKLM/HKCU Policies\Microsoft\Edge: ExtensionInstallBlocklist / DeveloperToolsAvailability / ExtensionAllowedTypes = **unset** → unpacked OK.
- 로드: **edge://extensions** → **개발자 모드 ON** → **압축을 푼 확장 로드** → `F:\claude\01 개발 프로그램\pen도우미\chrome-ext`
- Chrome과 동일 폴더. 샷: 20-edge-extensions.png

## 기능 목록
| 기능 | 하는 일 | 사용법 | 샷 |
|---|---|---|---|
| 바로가기 홈 | 결재/공람/포털 타일 + 도구·복무(채우기만) | 앱 / 사이드「바로가기」 | 01-standalone-home.png, 10-page-home-tools.png |
| 테마 4종 | 블랙·하늘·핑크·화이트 | 상단 테마 | 02~05-theme-*.png |
| 안내공문 | 공문→안내/과제 초안(로컬) | 「안내공문」 | 06-page-gongmun.png |
| 출장신청 | 출장 폼 채우기만 | 「출장신청」 | 07-page-travel.png |
| 할 일·일정 | 로컬 할 일/일정 | 「할 일·일정」 | 08-page-todo.png |
| 설정 | 로컬 설정·엑셀→과제카드 | 「설정」 | 09-page-settings.png |
| Chrome 확장 | 우측 레일 Alt+Shift+D | chrome://extensions 새로고침 후 포털 | 21/24-chrome-*.png |
| Edge 확장 | 동일 chrome-ext | edge://extensions 개발자모드 로드 | 20-edge-extensions.png |

## 사용자 확인
- Chrome/Edge에서 확장 **다시 로드**(v1.2.6) 후 포털 탭 새로고침 → 오른쪽 레일.
- Edge는 **개발자 모드**를 켜야 압축 해제 로드 가능(조직 관리 PC).

검증: Chrome 확장 오류 로그 삭제 후 1.2.6 다시 로드 → SyntaxError 소거 확인.
