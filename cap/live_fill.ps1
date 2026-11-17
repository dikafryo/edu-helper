$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile {
  param($Path,$Default)
  if (-not (Test-Path -LiteralPath $Path)) { return $Default }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default }
}
function Write-JsonFile {
  param($Path,$Object)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

$recv = Get-WxsWindows | Where-Object { $_.Pid -eq 20648 } | Select-Object -First 1
$tmpl = Get-WxsWindows | Where-Object { $_.Pid -eq 32372 } | Select-Object -First 1
if (-not $recv) { throw "recv missing" }
if (-not $tmpl) { throw "tmpl missing" }
"TYPE_HAS_FORCE=$([bool]([PenNoticeNative].GetMethod('ForceForeground')))"

# Read body
$body = Copy-TextFromHwpWindow -Hwnd $recv.Hwnd
"BODY_LEN=$($body.Length)"
if ($body.Length -lt 30) {
  # retry once
  Start-Sleep -Milliseconds 400
  $body = Copy-TextFromHwpWindow -Hwnd $recv.Hwnd
  "BODY_LEN2=$($body.Length)"
}
if ($body.Length -lt 30) { throw "body too short" }

$srcTitle = $recv.Title
$draftText = New-SchoolNoticeDraft -Title $srcTitle -Body $body
$utf8bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("F:\claude\01 개발 프로그램\pen도우미\cap\live_draft.txt", $draftText, $utf8bom)
$draftLines = @($draftText -split "`r?`n")
$fillTitle = $draftLines[0].Trim()
$fillBody = (($draftLines | Select-Object -Skip 1) -join "`r`n").TrimStart()
"FILL_TITLE=$fillTitle"
"FILL_BODY_LEN=$($fillBody.Length)"
"DRAFT_HEAD<<<"
($draftText.Substring(0, [Math]::Min(500, $draftText.Length)))
">>>END"

# Fill TITLE
Invoke-ActivateWindow -Hwnd $tmpl.Hwnd | Out-Null
$docTab = Find-NoticeDocInfoTabNode -Hwnd $tmpl.Hwnd
if ($docTab) { try { Invoke-AccDefault -Node $docTab | Out-Null } catch {}; Start-Sleep -Milliseconds 400 }
$edit = Find-NoticeTitleEditNode -Hwnd $tmpl.Hwnd
if ($null -eq $edit) { throw "title edit not found" }
"TITLE_NODE role=$($edit.Role) W=$($edit.W)"
$titleOk = Set-AccEditValue -Node $edit -Text $fillTitle
"TITLE_OK=$titleOk"
# verify
$nowTitle = ""
try { $nowTitle = [string]$edit.Acc.accValue($edit.Id) } catch {}
"TITLE_NOW_LEN=$($nowTitle.Length) PREVIEW=$($nowTitle.Substring(0,[Math]::Min(40,$nowTitle.Length)))"

# Fill BODY with formatting
$bodyTab = Find-NoticeBodyTabNode -Hwnd $tmpl.Hwnd
if ($bodyTab) { try { Invoke-AccDefault -Node $bodyTab | Out-Null } catch {}; Start-Sleep -Milliseconds 500 }
$hwp = Get-HwpBodyHwnd -Hwnd $tmpl.Hwnd
"HWP=$([int64]$hwp)"
$r = Format-PasteNoticeBodyToHwp -Hwnd $tmpl.Hwnd -Body $fillBody -ClearFirst `
  -TightenLetterSpacing -CharsPerLine 40 -SpillCharLimit 5 -MaxTightenSteps 6 `
  -ApplyBodyFont -BodyFontName "굴림" -BodyFontSize 12
"BODY_RESULT=$($r | ConvertTo-Json -Compress)"

# Screenshot template window
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ShotWin {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
}
"@
$rect = New-Object ShotWin+RECT
[void][ShotWin]::GetWindowRect($tmpl.Hwnd, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
"SHOT_SIZE=${w}x${h}"
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# PW_RENDERFULLCONTENT = 2
[void][ShotWin]::PrintWindow($tmpl.Hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$outShot = "F:\claude\01 개발 프로그램\pen도우미\cap\test1.png"
$bmp.Save($outShot, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"SHOT_OK=$(Test-Path $outShot) SIZE=$((Get-Item $outShot).Length)"
"DONE_NO_SAVE"