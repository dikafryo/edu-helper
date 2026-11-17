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
$acc = Get-IeAccFromHwnd -Hwnd $recv.Hwnd
"ACC_NULL=$($null -eq $acc)"
$nodes = Find-AccNodes -Root $acc -NameExact '제목' -MinW 80
"TITLE_NODES=$($nodes.Count)"
foreach ($e in @($nodes | Select-Object -First 3)) {
  $v = [string]$e.Value
  if ([string]::IsNullOrWhiteSpace($v)) { $v = [string]$e.Name }
  if ($v -match '__sId') { $v = '[masked]' }
  if ($v.Length -gt 50) { $v = $v.Substring(0,50)+'...' }
  "TITLE|$($e.Role)|W=$($e.W)|$v"
}
$btns = @()
foreach ($pat in @('*결재경로*','*수신자*','본문','결재올림','발송')) {
  $n = Find-AccNodes -Root $acc -NameLike $pat -MinW 5
  foreach ($x in @($n)) { $btns += ("{0}|{1}" -f $pat, $x.Name) }
}
"BTNS=$($btns -join ' ;; ')"
"BLOCK_결재올림=$(Test-BlockedAccName -Name '결재올림')"
"BLOCK_발송=$(Test-BlockedAccName -Name '발송')"
$r = Invoke-AccDefault -Node ([pscustomobject]@{ Name='결재올림'; Acc=$null; Id=0 })
"INVOKE_BLOCKED_RETURNS=$r"