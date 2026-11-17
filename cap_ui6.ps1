$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CapUi6 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int hgt,bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder sb, int max);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@
$dir='F:\claude\01 개발 프로그램\pen도우미'
$cap=Join-Path $dir 'cap'
New-Item -ItemType Directory -Force -Path $cap | Out-Null
function Get-PenProc { Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'PEN 업무 도우미' } | Select-Object -First 1 }
function Get-WinTitle([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 512
  [void][CapUi6]::GetWindowText($h, $sb, $sb.Capacity)
  return $sb.ToString()
}
function Restart-WithPage([string]$page) {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'PenHelper\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
  Start-Sleep 1
  [IO.File]::WriteAllText((Join-Path $cap '.select-page'), $page)
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe'
  $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$dir\PenHelper.ps1`""
  $psi.WorkingDirectory=$dir; $psi.UseShellExecute=$false
  [void][Diagnostics.Process]::Start($psi)
  for($i=0;$i -lt 50;$i++){
    Start-Sleep -Milliseconds 400
    $p=Get-PenProc
    if($p -and $p.MainWindowHandle -ne [IntPtr]::Zero){ return $p }
  }
  throw "PEN window not ready for $page"
}
function Save-Cap([IntPtr]$h,[string]$path){
  $title = Get-WinTitle $h
  if ($title -ne 'PEN 업무 도우미') {
    throw "Refuse capture: hwnd title='$title' (expected PEN 업무 도우미)"
  }
  $rr=New-Object CapUi6+RECT
  [void][CapUi6]::GetWindowRect($h,[ref]$rr)
  $w=$rr.R-$rr.L; $ht=$rr.B-$rr.T
  if ($w -lt 200 -or $ht -lt 200) { throw "bad size ${w}x${ht}" }
  $bmp=New-Object Drawing.Bitmap $w,$ht
  $g=[Drawing.Graphics]::FromImage($bmp)
  $hdc=$g.GetHdc()
  # PW_RENDERFULLCONTENT = 0x2
  $ok=[CapUi6]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc)
  if (-not $ok) {
    $g.CopyFromScreen($rr.L,$rr.T,0,0,$bmp.Size)
  }
  $g.Dispose()
  $bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Host "saved $path ${w}x${ht} title=$title print=$ok"
}
function Scroll-Down([IntPtr]$h,[int]$times=35){
  $rr=New-Object CapUi6+RECT; [void][CapUi6]::GetWindowRect($h,[ref]$rr)
  $cx=[int](($rr.L+$rr.R)/2+80); $cy=[int](($rr.T+$rr.B)/2)
  [void][CapUi6]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 80
  $pt=New-Object CapUi6+POINT; $pt.X=$cx; $pt.Y=$cy
  $target=[CapUi6]::WindowFromPoint($pt)
  for($i=0;$i -lt $times;$i++){
    $wp=[IntPtr](((-120) -shl 16))
    $lp=[IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
    [void][CapUi6]::SendMessage($target,0x020A,$wp,$lp)
  }
  Start-Sleep -Milliseconds 350
}
function Ensure-Foreground([IntPtr]$h) {
  [void][CapUi6]::ShowWindow($h,9)
  [void][CapUi6]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 400
  [void][CapUi6]::ShowWindow($h,5)
  [void][CapUi6]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 500
  $fg=[CapUi6]::GetForegroundWindow()
  $t=Get-WinTitle $fg
  Write-Host "fg=$t"
}
$pages=@(
  @{K='home'; F='ui6_home.png'},
  @{K='notice'; F='ui6_notice.png'; Bottom='ui6_notice_bottom.png'},
  @{K='trip'; F='ui6_trip.png'},
  @{K='todo'; F='ui6_todo.png'},
  @{K='settings'; F='ui6_settings.png'}
)
foreach($pg in $pages){
  $proc=Restart-WithPage $pg.K
  $h=$proc.MainWindowHandle
  [void][CapUi6]::MoveWindow($h,40,10,980,760,$true)
  Ensure-Foreground $h
  Save-Cap $h (Join-Path $cap $pg.F)
  if ($pg.ContainsKey('Bottom') -and $pg.Bottom) {
    Scroll-Down $h 40
    Start-Sleep -Milliseconds 400
    Ensure-Foreground $h
    Save-Cap $h (Join-Path $cap $pg.Bottom)
  }
}
Write-Host 'DONE'
Get-ChildItem $cap -Filter 'ui6_*.png' | ForEach-Object { Write-Host $_.Name $_.Length }
