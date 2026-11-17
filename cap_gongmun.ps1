$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class CapG {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
$dir='F:\claude\01 개발 프로그램\pen도우미'
$cap=Join-Path $dir 'cap'
New-Item -ItemType Directory -Force -Path $cap | Out-Null
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'PenHelper\.ps1|show_gongmun_dlg') } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 1
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='powershell.exe'
$psi.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$dir\show_gongmun_dlg.ps1`""
$psi.WorkingDirectory=$dir
$psi.UseShellExecute=$false
[void][Diagnostics.Process]::Start($psi)

$target=[IntPtr]::Zero
$title=''
for($i=0;$i -lt 60;$i++){
  Start-Sleep -Milliseconds 250
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $cond=New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window)
  $wins=$root.FindAll([System.Windows.Automation.TreeScope]::Children,$cond)
  foreach($w in $wins){
    $n=''
    try { $n=$w.Current.Name } catch { }
    if($n -match '공문접수'){
      $target=[IntPtr]$w.Current.NativeWindowHandle
      $title=$n
      break
    }
  }
  if($target -ne [IntPtr]::Zero){ break }
}
if($target -eq [IntPtr]::Zero){ throw 'gongmun dialog window not found via UIA' }
[void][CapG]::ShowWindow($target,9)
[void][CapG]::SetForegroundWindow($target)
Start-Sleep -Milliseconds 600
Write-Host ("target=$title hwnd=$target")
$rr=New-Object CapG+RECT
[void][CapG]::GetWindowRect($target,[ref]$rr)
$w=$rr.R-$rr.L; $ht=$rr.B-$rr.T
if($w -lt 200){ throw "bad size ${w}x${ht}" }
$bmp=New-Object Drawing.Bitmap $w,$ht
$g=[Drawing.Graphics]::FromImage($bmp)
$hdc=$g.GetHdc()
$ok=[CapG]::PrintWindow($target,$hdc,2)
$g.ReleaseHdc($hdc)
if(-not $ok){ $g.CopyFromScreen($rr.L,$rr.T,0,0,$bmp.Size) }
$g.Dispose()
$path=Join-Path $cap 'ui8_gongmun_dialog.png'
$bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "saved $path ${w}x${ht} print=$ok"
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'show_gongmun_dlg' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
