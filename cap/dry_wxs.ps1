$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
function Read-JsonFile { param($Path,$Default) if (-not (Test-Path $Path)) { return $Default }; try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default } }
function Write-JsonFile { param($Path,$Object) }
. 'F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1'
$wins = Get-WxsWindows
$wins | ForEach-Object { "{0}|{1}|{2}" -f $_.Kind, $_.Pid, $_.Title }
"COUNT=$($wins.Count)"