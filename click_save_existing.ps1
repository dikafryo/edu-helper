$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
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
  $utf8 = New-Object System.Text.UTF8Encoding $true
  [System.IO.File]::WriteAllText($Path, $json, $utf8)
}
function Open-InChrome { param([string]$Url) }

. 'F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1'
. 'F:\claude\01 개발 프로그램\pen도우미\PenGoogleCal.ps1'

$w = Get-GCalTargetWindow -PreferWithSave
if ($null -eq $w) { $w = Get-GCalTargetWindow }
if ($null -eq $w) { Write-Host 'NO_WIN'; exit 1 }
Write-Host ('WIN=' + $w.Current.Name)

$btn = Find-GCalSaveButton -Root $w -TimeoutMs 8000
if ($null -eq $btn) {
  Write-Host 'NO_BTN'
  $bc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
  $btns = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $bc)
  Write-Host ('btnCount=' + $btns.Count)
  $limit = [Math]::Min(60, $btns.Count)
  for ($i = 0; $i -lt $limit; $i++) {
    try {
      $n = [string]$btns.Item($i).Current.Name
      if ($n) { Write-Host ('B:' + $n) }
    } catch { }
  }
  exit 2
}

Write-Host ('BTN=' + $btn.Current.Name)
$ok = Invoke-UiaButton -Element $btn
Write-Host ('CLICK=' + $ok)
Start-Sleep -Milliseconds 1000
$ver = Wait-GCalSavedSignal -Root $w -ExpectTitle 'PEN' -TimeoutMs 15000
Write-Host ('VER_Ok=' + $ver.Ok + ' How=' + $ver.How)
if ($ver.Ok) {
  Set-GCalItemSaved -ItemId 'test-20261101141632' -Title 'PEN도우미 연동 시험' -DateYmd '2026-11-01' -Note $ver.How
  Write-Host 'MAP_SET=yes'
}
