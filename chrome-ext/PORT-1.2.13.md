# pen도우미 1.2.13 port report (Asia/Seoul)

Standalone 잔여 기능 → Chrome 확장 이식. 과제카드는 기존 유지.

| 기능 | 상태 | 비고 |
|---|---|---|
| 안내공문 helpers (붙임 번호, 굴림 12pt, 내어쓰기, 자간) | limited | 브라우저 텍스트/복사 + HWP 붙여넣기 체크리스트. HWP 창 자동화는 확장에서 불가 |
| 출장신청 fill | ported | FILL_TRAVEL + 원문추출(TRIP_DRAFT) → 채우기만 |
| 할 일 목록 | ported | chrome.storage.local, 긴급(기한초과) 우선 정렬 |
| 일정으로 등록 | ported | TODO_TO_SCHED |
| 구글 캘린더 저장 | ported | TEMPLATE URL 새 탭(제목·날짜 마스킹), host calendar.google.com only, 칩「구글 캘린더에 저장됨」 |
| 메신저/공람 배지 | limited | DOM 스캔만(쪽지/공람/결재). 데스크톱 메신저(ucware) 감시 없음, keep-alive/fetch 없음 |
| 그록 다듬기 | ported | 버튼 누를 때만 마스킹 패킷 복사 + 선택적 on-device polish/unmask |
| on-device Gemini Nano | ported | LanguageModel/Summarizer 있으면 사용, 없으면 heuristic fallback |
| 과제카드 | already | 기존 유지 |
| fill-only / 로컬 / Apple 테마 / 우측 레일 | kept | 상신·저장·결재·접수·발송 클릭 없음 |

버전: **1.2.13** · km79 Chrome 로드 · `node --check` 전 JS OK · 오류 버튼/Uncaught 0
