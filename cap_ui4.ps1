$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CapUi {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int hgt,bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumChildProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  public delegate bool EnumChildProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@

$proc = Get-Process powershell | Where-Object { $_.MainWindowTitle -match 'PEN' } | Select-Object -First 1
if (-not $proc) { throw 'no PEN process' }
$h = $proc.MainWindowHandle
Write-Host "pid=$($proc.Id) hwnd=$h"

[void][CapUi]::ShowWindow($h, 9)
[void][CapUi]::SetForegroundWindow($h)
[void][CapUi]::MoveWindow($h, 80, 20, 720, 1000, $true)
Start-Sleep -Milliseconds 400

$tabs = New-Object System.Collections.Generic.List[IntPtr]
$cb = [CapUi+EnumChildProc]{
  param($ch, $l)
  $sb = New-Object System.Text.StringBuilder 256
  [void][CapUi]::GetClassName($ch, $sb, 256)
  if ($sb.ToString() -eq 'SysTabControl32') { [void]$tabs.Add($ch) }
  $true
}
[void][CapUi]::EnumChildWindows($h, $cb, [IntPtr]::Zero)
Write-Host "tab controls: $($tabs.Count)"
foreach ($t in $tabs) {
  $cnt = [CapUi]::SendMessage($t, 0x1304, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
  Write-Host "tab=$t count=$cnt"
  # index 1 = 안내공문
  [void][CapUi]::SendMessage($t, 0x130C, [IntPtr]1, [IntPtr]::Zero)
  [void][CapUi]::PostMessage($t, 0x130C, [IntPtr]1, [IntPtr]::Zero)
}
# also physical click on second tab
$r = New-Object CapUi+RECT
[void][CapUi]::GetWindowRect($h, [ref]$r)
$x = $r.L + 160; $y = $r.T + 48
[void][CapUi]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 80
[CapUi]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
[CapUi]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Seconds 1

function Save-Cap([string]$path) {
  $rr = New-Object CapUi+RECT
  [void][CapUi]::GetWindowRect($h, [ref]$rr)
  $w = $rr.R - $rr.L; $ht = $rr.B - $rr.T
  if ($w -lt 50 -or $ht -lt 50) { throw "bad size ${w}x${ht}" }
  $bmp = New-Object System.Drawing.Bitmap $w, $ht
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rr.L, $rr.T, 0, 0, $bmp.Size)
  $g.Dispose()
  $dir = Split-Path $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "saved $path ${w}x${ht}"
}

Save-Cap 'F:\claude\01 개발 프로그램\pen도우미\cap\ui4.png'

# Scroll the notice panel to bottom via mouse wheel over content area
$cx = [int](($r.L + $r.R) / 2)
$cy = [int](($r.T + $r.B) / 2) + 80
[void][CapUi]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 100
# wheel down many times (delta -120 each)
for ($i=0; $i -lt 25; $i++) {
  [CapUi]::mouse_event(0x0800, 0, 0, [uint32]0xFF880000, [UIntPtr]::Zero) # negative wheel? use unchecked
}
# better: SendMessage WM_MOUSEWHEEL to window under cursor
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class Wheel {
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@
$pt = New-Object Wheel+POINT; $pt.X=$cx; $pt.Y=$cy
$target = [Wheel]::WindowFromPoint($pt)
Write-Host "wheel target=$target"
for ($i=0; $i -lt 40; $i++) {
  $wp = [IntPtr](((-120) -shl 16))
  $lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
  [void][Wheel]::SendMessage($target, 0x020A, $wp, $lp)
}
Start-Sleep -Milliseconds 400
Save-Cap 'F:\claude\01 개발 프로그램\pen도우미\cap\ui4_bottom.png'
Write-Host DONE
