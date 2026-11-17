$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param($Path,$Default) if (-not (Test-Path $Path)) { return $Default }; try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $Default } }
function Write-JsonFile { param($Path,$Object) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

function Dump-Interesting($Hwnd, $Label) {
  $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
  if ($null -eq $acc) { "$Label|NO_IE"; return }
  $all = Find-AccNodes -Root $acc -NameLike '*' -MinW 0 -MaxNodes 1500
  "$Label|COUNT=$($all.Count)"
  $keys = '제목','결재','수신','본문','경로','저장','서식','담당','성명','기안','탭'
  foreach ($n in @($all)) {
    $nm = [string]$n.Name
    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
    $hit = $false
    foreach ($k in $keys) { if ($nm -like "*$k*") { $hit = $true; break } }
    if (-not $hit -and $n.W -lt 80) { continue }
    if (-not $hit -and $nm.Length -lt 2) { continue }
    if (-not $hit) { continue }
    $safe = $nm
    if ($safe -match '__sId') { $safe = ($safe -replace '__sId=[^&\s]+','__sId=***') }
    if ($safe.Length -gt 70) { $safe = $safe.Substring(0,70)+'...' }
    "$Label|$($n.Role)|W=$($n.W)|A=$($n.Action)|$safe"
  }
}

$wins = Get-WxsWindows
foreach ($w in $wins) {
  "WIN|$($w.Kind)|$($w.Pid)|$($w.Title.Substring(0,[Math]::Min(40,$w.Title.Length)))"
  Dump-Interesting -Hwnd $w.Hwnd -Label $w.Kind
}