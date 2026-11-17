$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
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
$script:UiFontUi = New-Object System.Drawing.Font('맑은 고딕', 12)
$script:UiFontBtn = New-Object System.Drawing.Font('맑은 고딕', 11, [System.Drawing.FontStyle]::Bold)
$script:UiFontSection = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
$script:UiFontCaption = New-Object System.Drawing.Font('맑은 고딕', 9)
$script:UiBg = [System.Drawing.Color]::Black
$script:UiCard = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E')
$script:UiTile = [System.Drawing.ColorTranslator]::FromHtml('#2C2C2E')
$script:UiAccent = [System.Drawing.ColorTranslator]::FromHtml('#0A84FF')
$script:UiText = [System.Drawing.Color]::White
$script:UiMuted = [System.Drawing.ColorTranslator]::FromHtml('#98989D')
$script:UiDanger = [System.Drawing.ColorTranslator]::FromHtml('#FF453A')
. (Join-Path $root 'PenExtras.ps1')
$samplePath = Join-Path $root 'gongmun_sample.json'
$sample = $null
if (Test-Path -LiteralPath $samplePath) {
  $sample = [System.IO.File]::ReadAllText($samplePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
$title = if ($sample) { [string]$sample.Title } else { '' }
$body = if ($sample) { [string]$sample.Body } else { '' }
Show-GongmunTaskCardDialog -Title $title -Body $body
