$files = @(
  'F:\claude\01 개발 프로그램\pen도우미\PenHelper.ps1',
  'F:\claude\01 개발 프로그램\pen도우미\PenNoticeUi.ps1',
  'F:\claude\01 개발 프로그램\pen도우미\PenGoogleCal.ps1',
  'F:\claude\01 개발 프로그램\pen도우미\test_gcal_once.ps1'
)
foreach ($f in $files) {
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tok, [ref]$err)
  if ($err -and $err.Count) {
    Write-Host "FAIL $f"
    $err | ForEach-Object { $_.ToString() }
  } else {
    Write-Host "OK $f"
  }
}
