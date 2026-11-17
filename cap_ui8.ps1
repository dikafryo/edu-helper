$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CapUi8 {
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
  [void][CapUi8]::GetWindowText($h, $sb, $sb.Capacity)
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
  $rr=New-Object CapUi8+RECT
  [void][CapUi8]::GetWindowRect($h,[ref]$rr)
  $w=$rr.R-$rr.L; $ht=$rr.B-$rr.T
  if ($w -lt 200 -or $ht -lt 200) { throw "bad size ${w}x${ht}" }
  $bmp=New-Object Drawing.Bitmap $w,$ht
  $g=[Drawing.Graphics]::FromImage($bmp)
  $hdc=$g.GetHdc()
  # PW_RENDERFULLCONTENT = 0x2
  $ok=[CapUi8]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc)
  if (-not $ok) {
    $g.CopyFromScreen($rr.L,$rr.T,0,0,$bmp.Size)
  }
  $g.Dispose()
  $bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Host "saved $path ${w}x${ht} title=$title print=$ok"
}
function Scroll-Down([IntPtr]$h,[int]$times=35){
  $rr=New-Object CapUi8+RECT; [void][CapUi8]::GetWindowRect($h,[ref]$rr)
  $cx=[int](($rr.L+$rr.R)/2+80); $cy=[int](($rr.T+$rr.B)/2)
  [void][CapUi8]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 80
  $pt=New-Object CapUi8+POINT; $pt.X=$cx; $pt.Y=$cy
  $target=[CapUi8]::WindowFromPoint($pt)
  for($i=0;$i -lt $times;$i++){
    $wp=[IntPtr](((-120) -shl 16))
    $lp=[IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
    [void][CapUi8]::SendMessage($target,0x020A,$wp,$lp)
  }
  Start-Sleep -Milliseconds 350
}
function Ensure-Foreground([IntPtr]$h) {
  [void][CapUi8]::ShowWindow($h,9)
  [void][CapUi8]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 400
  [void][CapUi8]::ShowWindow($h,5)
  [void][CapUi8]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 500
  $fg=[CapUi8]::GetForegroundWindow()
  $t=Get-WinTitle $fg
  Write-Host "fg=$t"
}
$data = Join-Path $env:LOCALAPPDATA 'PenHelper'
New-Item -ItemType Directory -Force -Path $data | Out-Null
$settings = Join-Path $data 'settings.json'
function Set-ThemeFile([string]$theme) {
  $json = (@{ Theme = $theme; Updated = (Get-Date -Format 'o') } | ConvertTo-Json)
  $utf8bom = New-Object System.Text.UTF8Encoding $true
  [IO.File]::WriteAllText($settings, $json, $utf8bom)
}
# theme home shots
foreach($th in @('black','sky','pink','white')){
  Set-ThemeFile $th
  $proc = Restart-WithPage 'home'
  $h = $proc.MainWindowHandle
  [void][CapUi8]::MoveWindow($h,40,10,980,760,$true)
  Ensure-Foreground $h
  Start-Sleep -Milliseconds 600
  Save-Cap $h (Join-Path $cap ("ui8_{0}_home.png" -f $th))
}
# settings (theme pills) + todo
Set-ThemeFile 'black'
foreach($pg in @(
  @{K='settings'; F='ui8_settings.png'},
  @{K='todo'; F='ui8_todo.png'}
)){
  $proc=Restart-WithPage $pg.K
  $h=$proc.MainWindowHandle
  [void][CapUi8]::MoveWindow($h,40,10,980,760,$true)
  Ensure-Foreground $h
  Save-Cap $h (Join-Path $cap $pg.F)
}
# open 공문접수 dialog via temp flag? capture home then send click is hard —
# write a helper flag file that Shown handler can open dialog; instead capture via dedicated scriptlet
$flagDlg = Join-Path $cap '.open-gongmun'
[IO.File]::WriteAllText($flagDlg, '1')
# patch: use select-page home and a second flag read in Shown — if not wired, skip
# Wire quick: invoke by writing select and relying on existing Shown only for page —
# Capture settings is enough for themes; for dialog run inline after start:
$proc = Restart-WithPage 'home'
$h = $proc.MainWindowHandle
[void][CapUi8]::MoveWindow($h,40,10,980,760,$true)
Ensure-Foreground $h
# Try to click 공문접수 tile by screen position approx (left content tiles)
# Safer: use UIA to invoke button named/containing 공문접수
try {
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -EA SilentlyContinue | Out-Null
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $nameCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'PEN 업무 도우미')
  $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $nameCond)
  if ($win) {
    $btnCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    foreach ($b in $btns) {
      $n = ''
      try { $n = $b.Current.Name } catch { }
      if ($n -match '공문접수') {
        try {
          $ip = $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
          if ($ip) { $ip.Invoke(); Start-Sleep -Milliseconds 900; break }
        } catch { }
      }
    }
  }
  Start-Sleep -Milliseconds 800
  # capture foreground (dialog or main)
  $fg = [CapUi8]::GetForegroundWindow()
  Save-Cap $fg (Join-Path $cap 'ui8_gongmun_dialog.png')
} catch {
  Write-Host ('gongmun capture skip: ' + $_.Exception.Message)
}
Remove-Item -LiteralPath $flagDlg -Force -EA SilentlyContinue
Write-Host 'DONE'
Get-ChildItem $cap -Filter 'ui8_*.png' | ForEach-Object { Write-Host $_.Name $_.Length }
