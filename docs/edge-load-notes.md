# Edge unpacked 확장 (스토어/Partner Center 없음)

## 정책 점검 (읽기 전용, 2026-11-01 Asia/Seoul)
- HKLM\SOFTWARE\Policies\Microsoft\Edge: ExtensionInstallBlocklist / DeveloperToolsAvailability / ExtensionAllowedTypes = **unset**
- HKCU\SOFTWARE\Policies\Microsoft\Edge: 동일 **unset**
→ 개인용 압축 해제 확장 로드 가능.

## 로드 절차
1. 주소창: `edge://extensions`
2. **개발자 모드** ON
3. **압축을 푼 확장 로드**
4. 폴더: `F:\claude\01 개발 프로그램\pen도우미\chrome-ext`
5. 업데이트 후 **다시 로드** + 포털 탭 새로고침

Chrome과 **동일 chrome-ext 폴더** (MV3, sidePanel 없음, 우측 레일).