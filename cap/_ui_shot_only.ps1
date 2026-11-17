$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param([string]$Path,$Default); if (-not (Test-Path -LiteralPath $Path)) { return $Default }; try { $raw=[System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8); if ([string]::IsNullOrWhiteSpace($raw)){return $Default}; return ($raw|ConvertFrom-Json) } catch { return $Default } }
function Write-JsonFile { param([string]$Path,$Object); $json=$Object|ConvertTo-Json -Depth 8; $u=New-Object System.Text.UTF8Encoding $true; [System.IO.File]::WriteAllText($Path,$json,$u) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class FindPh2 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public static List<long> Matches = new List<long>();
  public static uint TargetPid;
  public static bool Cb(IntPtr h, IntPtr lp) {
    uint pid; GetWindowThreadProcessId(h, out pid);
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
[FindPh2]::TargetPid = [uint32]$targetPid
[FindPh2]::Matches = New-Object "System.Collections.Generic.List[long]"
$del = [FindPh2+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [FindPh2]::Cb($h,$lp) }
[FindPh2]::EnumWindows($del, [IntPtr]::Zero)
Write-Output ("PH_WINS=" + ([FindPh2]::Matches -join ","))
$phHwnd = [IntPtr]::Zero
foreach ($id in [FindPh2]::Matches) {
  $h = [IntPtr]$id
  $sb = New-Object System.Text.StringBuilder 512
  [void][FindPh2]::GetWindowText($h, $sb, 512)
  $t = $sb.ToString()
  Write-Output ("PH_WIN " + $id + " [" + $t + "]")
  if ($t -match "도우미|PenHelper|PEN") { $phHwnd = $h }
}
if ($phHwnd -eq [IntPtr]::Zero -and [FindPh2]::Matches.Count -gt 0) { $phHwnd = [IntPtr]([FindPh2]::Matches[0]) }
if ($phHwnd -eq [IntPtr]::Zero) { Write-Output "PH_HWND_MISSING"; exit 4 }

[void][FindPh2]::ShowWindow($phHwnd, 9)
[void][FindPh2]::SetForegroundWindow($phHwnd)
Start-Sleep -Milliseconds 900

$r = New-Object "PenNoticeNative+RECT"
[void][PenNoticeNative]::GetWindowRect($phHwnd, [ref]$r)
$w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
Write-Output ("RECT " + $r.Left + "," + $r.Top + " " + $w + "x" + $hgt)
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w,$hgt)))
$g.Dispose()
$out = "F:\claude\01 개발 프로그램\pen도우미\cap\ui.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("SHOT_OK " + $out + " bytes=" + (Get-Item $out).Length)
Write-Output "DONE"