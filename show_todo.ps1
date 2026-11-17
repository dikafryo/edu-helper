$flag = 'F:\claude\01 개발 프로그램\pen도우미\cap\.select-page'
[IO.File]::WriteAllText($flag, 'todo')
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'PenHelper\.ps1' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 1
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','F:\claude\01 개발 프로그램\pen도우미\PenHelper.ps1' -WorkingDirectory 'F:\claude\01 개발 프로그램\pen도우미'
Write-Host 'started'
