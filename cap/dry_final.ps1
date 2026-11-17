$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile {
  param($Path,$Default)
  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default }
}
function Write-JsonFile {
  param($Path,$Object)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"
. "F:\claude\01 개발 프로그램\pen도우미\PenNoticeUi.ps1"
"ADDTAB=$(Get-Command Add-NoticeTab -EA SilentlyContinue | % Name)"
"FMT=$(Get-Command Format-PasteNoticeBodyToHwp -EA SilentlyContinue | % Name)"
"FONT=$(Get-Command Apply-HangulBodyFont -EA SilentlyContinue | % Name)"
"TITLE_FN=$(Get-Command Find-NoticeTitleEditNode -EA SilentlyContinue | % Name)"
"SETTINGS_FONT=$($script:Settings.BodyFontName)/$($script:Settings.BodyFontSize)/Apply=$($script:Settings.ApplyBodyFont)"
"SETTINGS_TIGHTEN=$($script:Settings.TightenLetterSpacing) CPL=$($script:Settings.CharsPerLine)"

# spill estimate
$short = "1. " + ("가" * 38)
$spill = "1. " + ("가" * 42)
"W_SHORT=$(Get-NoticeDisplayWidth -S $short) SPILL_SHORT=$(Test-NoticeSmallSpill -Line $short -CharsPerLine 40 -SpillLimit 5)"
"W_SPILL=$(Get-NoticeDisplayWidth -S $spill) SPILL_OK=$(Test-NoticeSmallSpill -Line $spill -CharsPerLine 40 -SpillLimit 5)"

# targets dry
$tmpl = Get-WxsWindows | Where-Object Kind -eq template | Select-Object -First 1
$recv = Get-WxsWindows | Where-Object Kind -eq received | Select-Object -First 1
"TMPL_PID=$($tmpl.Pid) RECV_PID=$($recv.Pid)"
if ($tmpl) {
  $ie = Get-IeServerHwnd -Hwnd $tmpl.Hwnd
  $hwp = Get-HwpBodyHwnd -Hwnd $tmpl.Hwnd
  $edit = Find-NoticeTitleEditNode -Hwnd $tmpl.Hwnd
  "TITLE_TARGET=IE=$([int64]$ie) editRole=$($edit.Role) W=$($edit.W) H=$($edit.H) Name=$($edit.Name)"
  "BODY_TARGET=HwpMainEditWnd=$([int64]$hwp)"
}
# mask smoke
$m = Mask-PersonalInfo -Text "담당자: 홍길동`n전화: 051-111-2222`n해운대고등학교"
"MASK_PAIRS=$($m.Pairs.Count) KEEP_SCHOOL=$($m.Masked -match '해운대고등학교')"
"BLOCK=$(Test-BlockedAccName -Name '결재올림')"