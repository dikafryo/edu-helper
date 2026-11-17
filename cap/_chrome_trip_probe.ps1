$ErrorActionPreference = "Continue"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$utf8bom = New-Object System.Text.UTF8Encoding $true
$outDir = "F:\claude\01 개발 프로그램\pen도우미\cap"

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class ChromeEnum {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static List<long> Wins = new List<long>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls = new StringBuilder(256); GetClassName(h, cls, 256);
    if (cls.ToString() == "Chrome_WidgetWin_1") {
      var title = new StringBuilder(512); GetWindowText(h, title, 512);
      if (title.Length > 0) Wins.Add(h.ToInt64());
    }
    return true;
  }
}
"@

[ChromeEnum]::Wins = New-Object "System.Collections.Generic.List[long]"
$del = [ChromeEnum+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [ChromeEnum]::Cb($h,$lp) }
[ChromeEnum]::EnumWindows($del, [IntPtr]::Zero)
$fg = [ChromeEnum]::GetForegroundWindow()
$sbFg = New-Object System.Text.StringBuilder 512
[void][ChromeEnum]::GetWindowText($fg, $sbFg, 512)
$clsFg = New-Object System.Text.StringBuilder 256
[void][ChromeEnum]::GetClassName($fg, $clsFg, 256)
Write-Output ("FG hwnd={0} cls={1} title={2}" -f [int64]$fg, $clsFg.ToString(), $sbFg.ToString())
Write-Output ("CHROME_WINS=" + ([ChromeEnum]::Wins.Count))

function Get-UrlFromChrome([IntPtr]$Hwnd) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  # address bar: Edit control often name "주소창" or "Address and search bar" or contains http
  $condEdit = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edits = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condEdit)
  $urls = New-Object System.Collections.Generic.List[string]
  foreach ($e in $edits) {
    $name = ""; $val = ""
    try { $name = $e.Current.Name } catch {}
    try {
      $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      if ($vp) { $val = $vp.Current.Value }
    } catch {}
    if ($val -match '^https?://' -or $name -match '주소|Address|검색|omnibox') {
      [void]$urls.Add(("name=[{0}] val=[{1}]" -f $name, $val))
    }
  }
  return ,$urls.ToArray()
}

function Dump-FormFields([IntPtr]$Hwnd, [string]$OutPath) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $sb = New-Object System.Text.StringBuilder
  $stack = New-Object System.Collections.Stack
  $stack.Push(@{E=$el; D=0})
  $n=0
  $interestingTypes = @('edit','combo box','document','list','list item','radio button','check box','button','text','group','table','data item','tab item','menu item','hyperlink','spinner','pane')
  while ($stack.Count -gt 0 -and $n -lt 4000) {
    $cur = $stack.Pop(); $e=$cur.E; $d=[int]$cur.D
    if ($d -gt 18) { continue }
    $n++
    $name=""; $ct=""; $val=""; $auto=""; $help=""
    $x=0;$y=0;$w=0;$h=0
    try { $name = $e.Current.Name } catch {}
    try { $ct = $e.Current.LocalizedControlType } catch {}
    try { $auto = $e.Current.AutomationId } catch {}
    try { $help = $e.Current.HelpText } catch {}
    try {
      $r = $e.Current.BoundingRectangle
      $x=[int]$r.X; $y=[int]$r.Y; $w=[int]$r.Width; $h=[int]$r.Height
    } catch {}
    try {
      $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      if ($vp) { $val = $vp.Current.Value }
    } catch {}
    $hit = $false
    $nm = $name + " " + $val + " " + $auto
    if ($nm -match "출장|사유|일시|장소|관내|관외|시작|종료|구분|신청|교통|여비|목적지|기간|시간") { $hit = $true }
    if ($ct -match "edit|combo|radio|check|document|spinner") { $hit = $true }
    if ($d -le 2) { $hit = $true }
    if ($hit -and $w -ge 0) {
      [void]$sb.AppendLine(("d={0} type=[{1}] name=[{2}] val=[{3}] auto=[{4}] {5}x{6}@{7},{8}" -f $d, $ct, $name, $val, $auto, $w, $h, $x, $y))
    }
    $child = $walker.GetLastChild($e)
    $tmp = New-Object System.Collections.Generic.List[object]
    while ($null -ne $child) { $tmp.Add($child); $child = $walker.GetPreviousSibling($child) }
    foreach ($c in $tmp) { $stack.Push(@{E=$c; D=($d+1)}) }
  }
  [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), $utf8bom)
  Write-Output ("FIELDS " + $OutPath + " scanned=" + $n + " lines=" + (($sb.ToString() -split "`n").Count))
}

$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine(("time=" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")))
[void]$report.AppendLine(("FG=" + $sbFg.ToString()))

$targets = New-Object System.Collections.Generic.List[IntPtr]
# prefer FG if chrome
if ($clsFg.ToString() -eq "Chrome_WidgetWin_1") { [void]$targets.Add($fg) }
foreach ($id in [ChromeEnum]::Wins) {
  $h = [IntPtr]$id
  if (-not $targets.Contains($h)) { [void]$targets.Add($h) }
}

$i=0
foreach ($h in $targets) {
  $i++
  $title = New-Object System.Text.StringBuilder 512
  [void][ChromeEnum]::GetWindowText($h, $title, 512)
  Write-Output ("WIN" + $i + " hwnd=" + [int64]$h + " [" + $title.ToString() + "]")
  [void]$report.AppendLine(("WIN" + $i + " hwnd=" + [int64]$h + " title=" + $title.ToString()))
  try {
    $urls = @(Get-UrlFromChrome $h)
    foreach ($u in $urls) {
      Write-Output ("URL " + $u)
      [void]$report.AppendLine("URL " + $u)
    }
  } catch { Write-Output ("URL_FAIL " + $_); [void]$report.AppendLine("URL_FAIL " + $_) }
  $fieldPath = Join-Path $outDir ("chrome_trip_fields_" + $i + ".txt")
  try { Dump-FormFields $h $fieldPath } catch { Write-Output ("FIELD_FAIL " + $_) }
  # also save title-focused dump if title matches 출장
  if ($title.ToString() -match "출장") {
    Write-Output "HIT_TITLE_출장"
    [void]$report.AppendLine("HIT_TITLE_출장")
  }
}

$repPath = Join-Path $outDir "chrome_trip_report.txt"
[System.IO.File]::WriteAllText($repPath, $report.ToString(), $utf8bom)
Write-Output ("REPORT " + $repPath)
Write-Output "DONE"