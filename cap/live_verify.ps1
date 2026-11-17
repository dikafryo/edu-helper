$ErrorActionPreference="Stop"
[Console]::OutputEncoding=[Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:DataDir=Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile{param($Path,$Default); if(-not(Test-Path -LiteralPath $Path)){return $Default}; try{Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{$Default}}
function Write-JsonFile{param($Path,$Object)}
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

$tmpl=Get-WxsWindows|?{$_.Pid -eq 32372}|Select -First 1
if(-not $tmpl){throw "tmpl missing"}
Invoke-ActivateWindow -Hwnd $tmpl.Hwnd|Out-Null
Start-Sleep -Milliseconds 400

# read title back
$edit=Find-NoticeTitleEditNode -Hwnd $tmpl.Hwnd
$titleNow=""
if($edit){ try{$titleNow=[string]$edit.Acc.accValue($edit.Id)}catch{} }
"TITLE_BACK=$titleNow"

# switch to body tab and try copy body (careful - don't destroy)
$bodyTab=Find-NoticeBodyTabNode -Hwnd $tmpl.Hwnd
if($bodyTab){ try{Invoke-AccDefault -Node $bodyTab|Out-Null}catch{}; Start-Sleep -Milliseconds 400 }
# copy without clear-all destroy: select all copy then Escape? Risky. Use ^a^c then restore via undo? 
# Better: just screenshot for visual verify; optional copy
$bodySample=""
try {
  Invoke-ActivateWindow -Hwnd $tmpl.Hwnd|Out-Null
  $hwp=Get-HwpBodyHwnd -Hwnd $tmpl.Hwnd
  [void][PenNoticeNative]::ForceForeground($tmpl.Hwnd)
  try{[void][PenNoticeNative]::SetFocus($hwp)}catch{}
  Start-Sleep -Milliseconds 200
  try{[System.Windows.Forms.Clipboard]::Clear()}catch{}
  [System.Windows.Forms.SendKeys]::SendWait("^a"); Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait("^c"); Start-Sleep -Milliseconds 300
  $bodySample=[System.Windows.Forms.Clipboard]::GetText()
  # deselect
  [System.Windows.Forms.SendKeys]::SendWait("{RIGHT}")
} catch { "BODY_COPY_ERR=$($_.Exception.Message)" }
"BODY_BACK_LEN=$($bodySample.Length)"
if($bodySample.Length -gt 0){
  $prev=$bodySample.Substring(0,[Math]::Min(350,$bodySample.Length))
  "BODY_BACK<<<"; $prev; ">>>END"
}

# Screen capture via CopyFromScreen
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinRect2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
$r=New-Object WinRect2+RECT
[void][WinRect2]::GetWindowRect($tmpl.Hwnd,[ref]$r)
[void][WinRect2]::SetForegroundWindow($tmpl.Hwnd)
Start-Sleep -Milliseconds 300
$w=$r.R-$r.L; $h=$r.B-$r.T
"RECT=$($r.L),$($r.T) ${w}x${h}"
$bmp=New-Object System.Drawing.Bitmap $w,$h
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L,$r.T,0,0,(New-Object System.Drawing.Size($w,$h)))
$g.Dispose()
$path="F:\claude\01 개발 프로그램\pen도우미\cap\test1.png"
$bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"SHOT2_SIZE=$((Get-Item $path).Length)"