$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param($Path,$Default) if (-not (Test-Path $Path)) { return $Default }; try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $Default } }
function Write-JsonFile { param($Path,$Object) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

function Find-TitleCandidates($Hwnd) {
  $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
  if ($null -eq $acc) { return @() }
  $nodes = Find-AccNodes -Root $acc -NameLike '*제목*' -MinW 0 -MaxNodes 900
  $out = @()
  foreach ($n in @($nodes)) {
    $role = [string]$n.Role
    $isEdit = ($role -eq '42' -or $role -eq 'editable text' -or $role -match 'edit')
    $out += [pscustomobject]@{ Role=$role; W=[int]$n.W; H=[int]$n.H; Name=[string]$n.Name; Value=([string]$n.Value); Action=[string]$n.Action; IsEdit=$isEdit; Acc=$n.Acc; Id=$n.Id }
  }
  return $out
}

$wins = Get-WxsWindows
foreach ($w in $wins) {
  "=== $($w.Kind) pid=$($w.Pid) ==="
  $hwp = [PenNoticeNative]::FindChildByClass($w.Hwnd, 'HwpMainEditWnd')
  $ie = [PenNoticeNative]::FindChildByClass($w.Hwnd, 'Internet Explorer_Server')
  "HWP=$([int64]$hwp) IE=$([int64]$ie)"
  $cands = Find-TitleCandidates -Hwnd $w.Hwnd
  "TITLE_NAME_HITS=$($cands.Count)"
  $cands | Sort-Object W -Descending | Select-Object -First 8 | ForEach-Object {
    $v = $_.Value; if ($v.Length -gt 35) { $v = $v.Substring(0,35)+'...' }
    "  edit=$($_.IsEdit) R=$($_.Role) W=$($_.W)x$($_.H) N=$($_.Name) V=$v"
  }
  # also wide edits even if name not 제목
  $acc = Get-IeAccFromHwnd -Hwnd $w.Hwnd
  if ($acc) {
    $wide = Find-AccNodes -Root $acc -NameLike '*' -MinW 200 -MaxNodes 900
    $edits = @($wide | Where-Object { [string]$_.Role -eq '42' -and $_.W -ge 200 })
    "WIDE_EDIT42=$($edits.Count)"
    $edits | Select-Object -First 6 | ForEach-Object {
      $nm = $_.Name; if ($nm.Length -gt 40) { $nm = $nm.Substring(0,40)+'...' }
      $v = [string]$_.Value; if ($v.Length -gt 30) { $v = $v.Substring(0,30)+'...' }
      if ($nm -match '__sId') { $nm = '[masked-name]' }
      "  W=$($_.W) N=$nm V=$v"
    }
  }
}