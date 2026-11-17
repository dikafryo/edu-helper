PEN 업무 도우미 2차 (개인용)

파일: PenHelper.cmd / PenHelper.ps1 / PenNotice.ps1 / PenNoticeUi.ps1
실행: PenHelper.cmd 더블클릭 (트레이)

[안내공문 탭]
1) 원문읽기 → 로컬초안 또는 「그록에게 공문 다듬기」(버튼 누를 때만)
2) 그록 다듬기: PC에서 개인정보 마스킹 → 미리보기 → outbox\<시각>.txt 저장 + 클립보드
   헤더 '안내공문으로 바꿔줘' / 네트워크 전송 없음 / 마스크맵은 maskmaps에 보관
3) 「그록 결과 붙여넣기」: 자리표시자 복원
4) 제목→기안창 / 본문→기안창 은 서로 다른 컨트롤
   - 제목: 기안 WXSClient > Internet Explorer_Server > MSAA Name=제목 (role 42 한 줄)
   - 본문: 같은 기안창 > HwpMainEditWnd (한글 편집기). 본문 탭 전환 후 항목별 붙여넣기

[본문 채우기 규칙 — Format-PasteNoticeBodyToHwp]
- '1. '/'가. ' 직후 내어쓰기: Alt+Tab (표 안 체크 시 Alt+Shift+Tab)
- (옵션 체크) 줄바꿈 시 5글자 이하만 다음 줄로 넘어가면 단락 선택 후 Alt+Shift+J 우선, 이어서 Alt+Shift+N 반복(상한 MaxTightenSteps)
- 줄간격·단락 스타일은 템플릿 유지 (변경 안 함)
- (옵션 체크) 본문 삽입 후 글자모양 굴림 12pt (Alt+L, settings: BodyFontName/BodyFontSize/ApplyBodyFont)
- 한계: 넘침 판정은 CharsPerLine 추정(기본 40, settings.json). HWP UIA 줄정보 없음. 글꼴 대화상자는 버전차 가능.
  MaxTightenSteps(기본 6) 이상 자간은 줄이지 않음. 글꼴/용지에 따라 오차 가능.

[안전]
- 결재올림·발송·상신 절대 클릭 안 함
- 데이터: %LOCALAPPDATA%\PenHelper\ , 그록 전송본 F:\claude\01 개발 프로그램\pen도우미\outbox\
