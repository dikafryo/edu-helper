Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
$script:TaskCardsPath = Join-Path $script:DataDir 'task_cards.json'
$script:TaskCardRulesPath = Join-Path $script:DataDir 'task_card_rules.json'

function Get-TaskCards {
  if (-not (Test-Path -LiteralPath $script:TaskCardsPath)) { return ,@() }
  try {
    $raw = Get-Content -LiteralPath $script:TaskCardsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,@() }
    $j = $raw | ConvertFrom-Json
    if ($null -eq $j) { return ,@() }
    $arr = @($j)
    return ,$arr
  } catch { return ,@() }
}
function Save-TaskCards {
  param($Cards)
  $list = New-Object System.Collections.Generic.List[object]
  if ($null -ne $Cards) { foreach ($c in $Cards) { [void]$list.Add($c) } }
  $json = ($list.ToArray() | ConvertTo-Json -Depth 8)
  if ($null -eq $json -or $json -eq '') { $json = '[]' }
  [System.IO.File]::WriteAllText($script:TaskCardsPath, [string]$json, (New-Object System.Text.UTF8Encoding $true))
}
function Get-TaskCardRules {
  if (-not (Test-Path -LiteralPath $script:TaskCardRulesPath)) { return [pscustomobject]@{ Rules=@(); History=@() } }
  try {
    $j = Get-Content -LiteralPath $script:TaskCardRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $j) { return [pscustomobject]@{ Rules=@(); History=@() } }
    return $j
  } catch { return [pscustomobject]@{ Rules=@(); History=@() } }
}
function Write-JsonFile {
  param([string]$Path, $Object)
  $json = ($Object | ConvertTo-Json -Depth 10)
  [System.IO.File]::WriteAllText($Path, [string]$json, (New-Object System.Text.UTF8Encoding $true))
}

$dir = 'F:\claude\01 개발 프로그램\pen도우미'
. (Join-Path $dir 'PenTaskCardExcel.ps1')
$xlsx = Join-Path $env:LOCALAPPDATA 'PenHelper\import\upload.xlsx'
Write-Host "xlsx=$xlsx before=$((Get-TaskCards).Count)"
$r = Import-TaskCardsFromExcel -Path $xlsx -Mode Merge -NoUI
Write-Host ("OK Mode=$($r.Mode) CardsTotal=$($r.CardsTotal) FromExcel=$($r.CardsFromExcel) SourceRows=$($r.SourceRows) Backup=$($r.Backup)")
Write-Host "after=$((Get-TaskCards).Count)"
Get-Content (Join-Path $script:DataDir 'task_card_import_meta.json') -Encoding UTF8 | Select-Object -First 20
