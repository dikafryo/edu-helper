$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$script:AppName = 'PEN 업무 도우미'
$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

function Read-JsonFile {
  param([string]$Path, $Default)
  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  try {
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    return ($raw | ConvertFrom-Json)
  } catch { return $Default }
}
function Write-JsonFile {
  param([string]$Path, $Object)
  $json = $Object | ConvertTo-Json -Depth 8
  $utf8bom = New-Object System.Text.UTF8Encoding $true
  [System.IO.File]::WriteAllText($Path, $json, $utf8bom)
}
function Open-InChrome {
  param([string]$Url)
  $candidates = @(
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { Start-Process -FilePath $c -ArgumentList @($Url); return }
  }
  Start-Process $Url
}

$notice = Join-Path $PSScriptRoot 'PenNotice.ps1'
if (Test-Path $notice) { . $notice }
. (Join-Path $PSScriptRoot 'PenGoogleCal.ps1')

$itemId = 'test-' + (Get-Date -Format 'yyyyMMddHHmmss')
$title = 'PEN도우미 연동 시험'
$date = (Get-Date).ToString('yyyy-MM-dd')
$body = '자동 저장 시험 (삭제하지 않음)'

Write-Host ("TEST itemId={0} title={1} date={2}" -f $itemId, $title, $date)
$r = Save-ScheduleToGoogleCalendar -ItemId $itemId -Title $title -DateYmd $date -Body $body
Write-Host ("RESULT Ok={0}" -f $r.Ok)
Write-Host ("RESULT Chip={0}" -f $(if ($r.PSObject.Properties['Chip']) { $r.Chip } else { '' }))
Write-Host ("RESULT Message={0}" -f $(if ($r.PSObject.Properties['Message']) { $r.Message } else { '' }))
Write-Host ("RESULT How={0}" -f $(if ($r.PSObject.Properties['How']) { $r.How } else { '' }))
Write-Host ("RESULT Title={0}" -f $(if ($r.PSObject.Properties['Title']) { $r.Title } else { '' }))
Write-Host ("RESULT Date={0}" -f $(if ($r.PSObject.Properties['Date']) { $r.Date } else { '' }))
if (Test-GCalItemSaved -ItemId $itemId) { Write-Host 'SAVED_MAP=yes' } else { Write-Host 'SAVED_MAP=no' }
# also persist into schedules.json so UI shows chip
$schedPath = Join-Path $script:DataDir 'schedules.json'
$arr = @()
$existing = Read-JsonFile -Path $schedPath -Default @()
foreach ($e in @($existing)) { $arr += $e }
$arr = @([pscustomobject]@{
  Id = $itemId; Title = $title; Body = $body; Date = $date
  Source = 'test'; Created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  GoogleSaved = [bool]$r.Ok
}) + @($arr)
Write-JsonFile -Path $schedPath -Object $arr
Write-Host 'DONE'
