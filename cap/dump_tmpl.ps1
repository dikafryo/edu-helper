$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param($Path,$Default) if (-not (Test-Path $Path)) { return $Default }; try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $Default } }
function Write-JsonFile { param($Path,$Object) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"
$tmpl = Get-WxsWindows | Where-Object Kind -eq 'template' | Select-Object -First 1
$acc = Get-IeAccFromHwnd -Hwnd $tmpl.Hwnd
foreach ($pat in @('제목','*수신*','*결재경로*','*저장결재*','*불러오기*','*프리셋*','*수신처*','*경로*')) {
  $nodes = Find-AccNodes -Root $acc -NameLike $pat -MinW 0 -MaxNodes 1500
  "PAT=$pat COUNT=$($nodes.Count)"
  foreach ($n in @($nodes | Select-Object -First 12)) {
    $v = [string]$n.Value
    if ($v.Length -gt 40) { $v = $v.Substring(0,40)+'...' }
    if ($v -match '__sId') { $v = '[masked]' }
    "  R=$($n.Role) W=$($n.W) A=$($n.Action) N=$($n.Name) V=$v"
  }
}
# wide role-42 edits
$all = Find-AccNodes -Root $acc -NameLike '*' -MinW 100 -MaxNodes 1500
"WIDE100=$($all.Count)"
foreach ($n in @($all | Where-Object { $_.Role -eq '42' -or $_.Role -eq 42 } | Select-Object -First 30)) {
  "WIDE|R=$($n.Role)|W=$($n.W)|N=$($n.Name)|V=$([string]$n.Value)"
}