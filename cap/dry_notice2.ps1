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
$wins | ForEach-Object { "WXS|$($_.Kind)|$($_.Pid)" }

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
"PAIR_COUNT=$($m.Pairs.Count)"
$m.Pairs | ForEach-Object { "PAIR|$($_.Kind)|$($_.Placeholder)" }
"HAS_NAME=$($m.Masked -match '\[이름')"
"HAS_PHONE=$($m.Masked -match '\[전화')"
"HAS_EMAIL=$($m.Masked -match '\[이메일')"
"HAS_RRN=$($m.Masked -match '\[주민번호')"
"HAS_ACCT=$($m.Masked -match '\[계좌')"
"HAS_ADDR=$($m.Masked -match '\[주소')"
"KEEP_SCHOOL=$($m.Masked -match '해운대고등학교')"
"KEEP_OFFICE=$($m.Masked -match '부산광역시교육청')"
"NO_HONG=$($m.Masked -notmatch '홍길동')"
$u = Unmask-PersonalInfo -Text $m.Masked -Pairs $m.Pairs
"UNMASK_OK=$($u -eq $sample)"
$draft = New-SchoolNoticeDraft -SourceTitle "직업계고 현장실습 안내" -SourceBody $sample
"DRAFT_TITLE=$($draft.Title)"
"DRAFT_ATTACH=$($draft.Body -match '붙임')"
"DRAFT_END=$($draft.Body -match '끝\.')"
"HEADER=$($script:Settings.GrokPromptHeader)"

# outbox write dry
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir = 'F:\claude\01 개발 프로그램\pen도우미\outbox'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$payload = $script:Settings.GrokPromptHeader + "`r`n`r`n" + $m.Masked
$outPath = Join-Path $outDir ($stamp + '.txt')
$utf8bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($outPath, $payload, $utf8bom)
$mapPath = Save-MaskMapFile -Pairs $m.Pairs -Stamp $stamp
"OUTBOX=$outPath"
"MAP=$mapPath"
"OUT_EXISTS=$(Test-Path $outPath)"
"MAP_EXISTS=$(Test-Path $mapPath)"