$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile {
  param($Path, $Default)
  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default }
}
function Write-JsonFile { param($Path, $Object) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"
$recv = Get-WxsWindows | Where-Object { $_.Kind -eq 'received' } | Select-Object -First 1
$tmpl = Get-WxsWindows | Where-Object { $_.Kind -eq 'template' } | Select-Object -First 1
$acc = Get-IeAccFromHwnd -Hwnd $recv.Hwnd
$edits = @(Find-AccNodes -Root $acc -Role 42)
"EDIT_COUNT=$($edits.Count)"
foreach ($e in ($edits | Select-Object -First 5)) {
  $v = ''
  try { $v = [string]$e.Acc.accValue($e.Id) } catch {}
  if ([string]::IsNullOrWhiteSpace($v)) { $v = [string]$e.Name }
  if ($v -match '__sId|session|token') { $v = '[masked-session]' }
  if ($v.Length -gt 60) { $v = $v.Substring(0,60) + '...' }
  "EDIT|$($e.Name)|$v"
}
# buttons of interest (names only)
$btns = @(Find-AccNodes -Root $acc -Role 43)
$names = @()
foreach ($b in $btns) {
  $n = [string]$b.Name
  if ($n -match '결재|수신|제목|본문|경로|저장|발송|상신') { $names += $n }
}
"BTN_INTEREST=$($names -join ' | ')"
# blocked invoke test (must refuse)
$fake = [pscustomobject]@{ Name = '결재올림'; Acc = $null; Id = 0 }
try {
  $r = Invoke-AccDefault -Node $fake
  "BLOCK_RESULT=$r"
} catch {
  "BLOCK_EX=$($_.Exception.Message)"
}
"TMPL_PID=$($tmpl.Pid)"