$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CapUi5 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int hgt,bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@

$dir='F:\claude\01 개발 프로그램\pen도우미'
$cap=Join-Path $dir 'cap'
New-Item -ItemType Directory -Force -Path $cap | Out-Null

function Get-PenProc {
  Get-Process powershell -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'PEN' } | Select-Object -First 1
}
function Restart-WithPage([string]$page) {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'PenHelper\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
  Start-Sleep 1
  $flag=Join-Path $cap '.select-page'
  [IO.File]::WriteAllText($flag, $page, [Text.UTF8Encoding]::new($false))
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe'
  $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$dir\PenHelper.ps1`""
  $psi.WorkingDirectory=$dir
  $psi.UseShellExecute=$false
  [void][Diagnostics.Process]::Start($psi)
  for($i=0;$i -lt 30;$i++){
    Start-Sleep -Milliseconds 400
    $p=Get-PenProc
    if($p -and $p.MainWindowHandle -ne [IntPtr]::Zero){ return $p }
  }
  throw "PEN window not ready for $page"
}
function Save-Cap([IntPtr]$h,[string]$path){
  $rr=New-Object CapUi5+RECT
  [void][CapUi5]::GetWindowRect($h,[ref]$rr)
  $w=$rr.R-$rr.L; $ht=$rr.B-$rr.T
  if($w -lt 50 -or $ht -lt 50){ throw "bad size ${w}x${ht}" }
  $bmp=New-Object Drawing.Bitmap $w,$ht
  $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rr.L,$rr.T,0,0,$bmp.Size)
  $g.Dispose()
  $bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "saved $path ${w}x${ht}"
}
function Scroll-Down([IntPtr]$h, [int]$times=30){
  $rr=New-Object CapUi5+RECT
  [void][CapUi5]::GetWindowRect($h,[ref]$rr)
  $cx=[int](($rr.L+$rr.R)/2 + 80)
  $cy=[int](($rr.T+$rr.B)/2)
  [void][CapUi5]::SetCursorPos($cx,$cy)
  Start-Sleep -Milliseconds 80
  $pt=New-Object CapUi5+POINT; $pt.X=$cx; $pt.Y=$cy
  $target=[CapUi5]::WindowFromPoint($pt)
  for($i=0;$i -lt $times;$i++){
    $wp=[IntPtr](((-120) -shl 16))
    $lp=[IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
    [void][CapUi5]::SendMessage($target,0x020A,$wp,$lp)
  }
  Start-Sleep -Milliseconds 300
}

$pages=@(
  @{K='home'; F='ui5_home.png'},
  @{K='notice'; F='ui5_notice.png'; Bottom='ui5_notice_bottom.png'},
  @{K='trip'; F='ui5_trip.png'},
  @{K='todo'; F='ui5_todo.png'},
  @{K='settings'; F='ui5_settings.png'}
)
foreach($pg in $pages){
  $proc=Restart-WithPage $pg.K
  $h=$proc.MainWindowHandle
  [void][CapUi5]::ShowWindow($h,9)
  [void][CapUi5]::SetForegroundWindow($h)
  [void][CapUi5]::MoveWindow($h,40,10,980,760,$true)
  Start-Sleep -Milliseconds 700
  Save-Cap $h (Join-Path $cap $pg.F)
  if($pg.Bottom){
    Scroll-Down $h 45
    Save-Cap $h (Join-Path $cap $pg.Bottom)
  }
}
Write-Host DONE
Get-ChildItem $cap\ui5_*.png | ForEach-Object { Write-Host $_.Name $_.Length }
