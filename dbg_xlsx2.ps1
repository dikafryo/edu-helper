$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root='F:\claude\01 개발 프로그램\pen도우미'
$script:DataDir=Join-Path $env:LOCALAPPDATA 'PenHelper'
function Read-JsonFile { param([string]$Path,$Default); if(-not(Test-Path -LiteralPath $Path)){return $Default}; try{ $raw=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8); if([string]::IsNullOrWhiteSpace($raw)){return $Default}; return ($raw|ConvertFrom-Json)}catch{return $Default}}
function Write-JsonFile { param([string]$Path,$Object); $json=$Object|ConvertTo-Json -Depth 10; $utf8=New-Object Text.UTF8Encoding $true; [IO.File]::WriteAllText($Path,$json,$utf8) }
. "$root\PenTaskCardExcel.ps1"
$path = Join-Path $script:DataDir 'import\upload.xlsx'
try {
  $rows = Read-ExcelRowsZipXml -Path $path -SheetName '단위사업카드'
  Write-Host ("rows=" + $rows.Count)
  $h = Find-ExcelHeaderMap -Rows $rows
  Write-Host ("headerRow=" + $h.HeaderRow)
  Write-Host ("map keys=" + ($h.Map.Keys -join ','))
  $built = Convert-ExcelRowsToTaskCards -Rows $rows -HeaderInfo $h
  Write-Host ("cards=" + $built.UniqueCards + " srcRows=" + $built.SourceRows)
} catch {
  Write-Host ("FAIL: " + $_.Exception.Message)
  Write-Host $_.ScriptStackTrace
  if ($_.InvocationInfo) { Write-Host ("at: " + $_.InvocationInfo.PositionMessage) }
}
