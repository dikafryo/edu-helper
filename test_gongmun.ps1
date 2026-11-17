$ErrorActionPreference = "Stop"
try {
  & "F:\claude\01 개발 프로그램\pen도우미\show_gongmun_dlg.ps1"
  "OK"
} catch {
  "ERR: $($_.Exception.Message)"
  $_.ScriptStackTrace
  if ($_.Exception.InnerException) { "INNER: $($_.Exception.InnerException.Message)" }
}
