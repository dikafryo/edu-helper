$ErrorActionPreference = "Continue"
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
try {
  . "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"
  "NOTICE_OK" | Write-Output
} catch { "NOTICE_FAIL " + $_.Exception.Message | Write-Output }
try {
  . "F:\claude\01 개발 프로그램\pen도우미\PenNoticeUi.ps1"
  "UI_OK" | Write-Output
  if (Get-Command Add-NoticeTab -ErrorAction SilentlyContinue) { "ADD_NOTICE_TAB_OK" | Write-Output } else { "ADD_NOTICE_TAB_MISSING" | Write-Output }
} catch { "UI_FAIL " + $_.Exception.Message | Write-Output; $_.ScriptStackTrace | Write-Output }