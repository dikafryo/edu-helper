$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
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
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

$tmplPid = 32372
$tmpl = Get-Process -Id $tmplPid -ErrorAction SilentlyContinue
if (-not $tmpl) { Write-Output "TMPL_GONE"; exit 2 }
$hwnd = $tmpl.MainWindowHandle
Write-Output ("TMPL_HWND=" + [int64]$hwnd)

$draftPath = "F:\claude\01 개발 프로그램\pen도우미\cap\live_draft.txt"
$draft = [System.IO.File]::ReadAllText($draftPath, (New-Object System.Text.UTF8Encoding $true))
$title = ($draft -split "`r?`n")[0].Trim()
Write-Output ("TITLE_LEN=" + $title.Length)

$doc = Find-NoticeDocInfoTabNode -Hwnd $hwnd
if ($doc) { Invoke-AccDefault -Node $doc | Out-Null; Start-Sleep -Milliseconds 350 }
$te = Find-NoticeTitleEditNode -Hwnd $hwnd
if ($te) {
  try { Write-Output ("TITLE_BEFORE=" + ([string]$te.accValue(0))) } catch { Write-Output "TITLE_BEFORE=?" }
  $ok = Set-AccEditValue -Node $te -Text $title
  Write-Output ("TITLE_SET=" + $ok)
  Start-Sleep -Milliseconds 250
  try { Write-Output ("TITLE_AFTER=" + ([string]$te.accValue(0))) } catch {}
} else {
  Write-Output "TITLE_NODE_MISSING"
}

function Capture-Hwnd([IntPtr]$h, [string]$outPath) {
  [void][PenNoticeNative]::ShowWindow($h, 9)
  try { [void][PenNoticeNative]::ForceForeground($h) } catch { [void][PenNoticeNative]::SetForegroundWindow($h) }
  Start-Sleep -Milliseconds 500
  $r = New-Object "PenNoticeNative+RECT"
  [void][PenNoticeNative]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left
  $hgt = $r.Bottom - $r.Top
  Write-Output ("RECT " + $r.Left + "," + $r.Top + " " + $w + "x" + $hgt)
  if ($w -lt 40 -or $hgt -lt 40) { throw ("bad size " + $w + "x" + $hgt) }
  $bmp = New-Object System.Drawing.Bitmap $w, $hgt
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $hgt)))
  $g.Dispose()
  $dir = Split-Path $outPath -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $len = (Get-Item $outPath).Length
  $bmp.Dispose()
  Write-Output ("SHOT_OK " + $outPath + " bytes=" + $len + " " + $w + "x" + $hgt)
}

Capture-Hwnd $hwnd "F:\claude\01 개발 프로그램\pen도우미\cap\test1.png"

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class FindPh {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public static List<long> Matches = new List<long>();
  public static uint TargetPid;
  public static bool Cb(IntPtr h, IntPtr lp) {
    uint pid;
    GetWindowThreadProcessId(h, out pid);
    if (pid == TargetPid) {
      var sb = new StringBuilder(512);
      GetWindowText(h, sb, 512);
      if (!string.IsNullOrEmpty(sb.ToString())) Matches.Add(h.ToInt64());
    }
    return true;
  }
}
"@

$phProc = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "PenHelper\.ps1" } | Select-Object -First 1
if (-not $phProc) { Write-Output "PH_PROC_MISSING"; exit 3 }
$targetPid = [int]$phProc.ProcessId
Write-Output ("PH_PID=" + $targetPid)
[FindPh]::TargetPid = [uint32]$targetPid
[FindPh]::Matches.Clear()
[FindPh]::EnumWindows([FindPh+EnumProc][FindPh]::Cb, [IntPtr]::Zero)
Write-Output ("PH_WINS=" + ([FindPh]::Matches -join ","))
$phHwnd = [IntPtr]::Zero
foreach ($id in [FindPh]::Matches) {
  $h = [IntPtr]$id
  $sb = New-Object System.Text.StringBuilder 512
  [void][FindPh]::GetWindowText($h, $sb, 512)
  $t = $sb.ToString()
  Write-Output ("PH_WIN " + $id + " [" + $t + "]")
  if ($t -match "도우미|PenHelper|PEN") { $phHwnd = $h }
}
if ($phHwnd -eq [IntPtr]::Zero -and [FindPh]::Matches.Count -gt 0) {
  $phHwnd = [IntPtr]([FindPh]::Matches[0])
}
if ($phHwnd -ne [IntPtr]::Zero) {
  [void][FindPh]::ShowWindow($phHwnd, 9)
  [void][FindPh]::SetForegroundWindow($phHwnd)
  Start-Sleep -Milliseconds 800
  Capture-Hwnd $phHwnd "F:\claude\01 개발 프로그램\pen도우미\cap\ui.png"
} else {
  Write-Output "PH_HWND_MISSING"
}
Write-Output "DONE"