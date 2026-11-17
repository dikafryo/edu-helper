$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
$script:DraftDir = Join-Path $script:DataDir "drafts"
foreach ($d in @($script:DataDir, $script:DraftDir)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
function Read-JsonFile {
  param($Path, $Default)
  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default }
}
function Write-JsonFile {
  param($Path, $Object)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"
$wins = Get-WxsWindows
"WXS_COUNT=$($wins.Count)"
$wins | ForEach-Object { "WXS|$($_.Kind)|$($_.Pid)|$($_.Title.Substring(0, [Math]::Min(40, $_.Title.Length)))" }

$sample = @"
제목: 직업계고 현장실습 안내
담당자: 홍길동
전화: 051-123-4567
이메일: hong@example.school.kr
주민번호: 900101-1234567
계좌: 123-456-789012
주소: 부산광역시 해운대구 우동 1번지
부산광역시교육청, 해운대교육지원청, 해운대고등학교
관련 내용을 안내합니다.
"@
$m = Mask-PersonalInfo -Text $sample
"MASKED_OK=$([bool]$m.Masked)"
"PAIR_COUNT=$($m.Pairs.Count)"
$m.Pairs | ForEach-Object { "PAIR|$($_.Kind)|$($_.Placeholder)|len=$($_.Value.Length)" }
"HAS_NAME=$($m.Masked -match '\[이름')"
"HAS_PHONE=$($m.Masked -match '\[전화')"
"KEEP_SCHOOL=$($m.Masked -match '해운대고등학교')"
"KEEP_OFFICE=$($m.Masked -match '부산광역시교육청')"
$u = Unmask-PersonalInfo -Text $m.Masked -Pairs $m.Pairs
"UNMASK_OK=$($u -eq $sample)"
$draft = New-SchoolNoticeDraft -SourceTitle "직업계고 현장실습 안내" -SourceBody $sample
"DRAFT_TITLE=$($draft.Title)"
"DRAFT_HAS_ATTACH=$($draft.Body -match '붙임')"
"DRAFT_HAS_END=$($draft.Body -match '끝\.')"
"HEADER=$($script:Settings.GrokPromptHeader)"