$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
$script:DraftDir = Join-Path $script:DataDir "drafts"
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
. "F:\claude\01 개발 프로그램\pen도우미\PenNoticeUi.ps1"
"HAS_ADDTAB=$(Get-Command Add-NoticeTab -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)"
$d = New-SchoolNoticeDraft -Title "직업계고 현장실습 안내" -Body "1. 관련: 없음`r`n2. 현장실습을 안내합니다.`r`n붙임 1. 일정표"
"DRAFT_LEN=$($d.Length)"
"DRAFT_HAS_SUBJECT=$($d -match '안내')"
"DRAFT_HAS_NUMGIM=$($d -match '넘김')"
"DRAFT_HAS_ATTACH=$($d -match '붙임')"
"DRAFT_HAS_END=$($d -match '끝\.')"

# dry read: title field via MSAA only (no HWP clipboard to avoid disturbing user)
$recv = Get-WxsWindows | Where-Object { $_.Kind -eq 'received' } | Select-Object -First 1
"RECV_PID=$($recv.Pid)"
$acc = Get-AccessibleFromHwnd -Hwnd $recv.Hwnd
$titleNode = Find-AccNodes -Root $acc -Role 42 -MinW 200 | Select-Object -First 1
if ($titleNode) {
  $tv = ''
  try { $tv = [string]$titleNode.Acc.accValue($titleNode.Id) } catch {}
  if (-not $tv) { try { $tv = [string]$titleNode.Name } catch {} }
  # mask any long token-looking substrings
  $tvSafe = $tv
  if ($tvSafe.Length -gt 80) { $tvSafe = $tvSafe.Substring(0,80) + '...' }
  "TITLE_LEN=$($tv.Length)"
  "TITLE_PREVIEW=$tvSafe"
} else {
  "TITLE_NODE=none"
}
# ensure blocked invoke list
$blocked = @('결재올림','발송','상신','재발송')
"BLOCK_LIST=$($blocked -join ',')"