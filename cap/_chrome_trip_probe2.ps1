$ErrorActionPreference = "Continue"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$utf8bom = New-Object System.Text.UTF8Encoding $true
$outDir = "F:\claude\01 개발 프로그램\pen도우미\cap"

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class ChromeEnum2 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static List<string> Lines = new List<string>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls = new StringBuilder(256); GetClassName(h, cls, 256);
    var title = new StringBuilder(512); GetWindowText(h, title, 512);
    string c = cls.ToString(); string t = title.ToString();
    if (c.IndexOf("Chrome") >= 0 || t.IndexOf("출장") >= 0 || t.IndexOf("신청") >= 0 || c == "Chrome_WidgetWin_1") {
      if (!string.IsNullOrEmpty(t) || c.IndexOf("Chrome") >= 0)
        Lines.Add(string.Format("h={0} cls=[{1}] title=[{2}]", h.ToInt64(), c, t));
    }
    return true;
  }
}
"@
[ChromeEnum2]::Lines = New-Object "System.Collections.Generic.List[string]"
$del = [ChromeEnum2+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [ChromeEnum2]::Cb($h,$lp) }
[ChromeEnum2]::EnumWindows($del, [IntPtr]::Zero)
$all = [ChromeEnum2]::Lines
$all | ForEach-Object { Write-Output $_ }
[System.IO.File]::WriteAllText((Join-Path $outDir "chrome_all_wins.txt"), ($all -join "`r`n"), $utf8bom)

# Deep dump edits with labels near 출장 purpose etc for every chrome win
function Dump-Edits([IntPtr]$Hwnd, [string]$Tag) {
  try {
    $el = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  } catch { return }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edits = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  $sb = New-Object System.Text.StringBuilder
  foreach ($e in $edits) {
    $name=""; $val=""; $x=0;$y=0;$w=0;$h=0
    try { $name=$e.Current.Name } catch {}
    try { $r=$e.Current.BoundingRectangle; $x=[int]$r.X; $y=[int]$r.Y; $w=[int]$r.Width; $h=[int]$r.Height } catch {}
    try { $vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $val=$vp.Current.Value } } catch {}
    [void]$sb.AppendLine(("EDIT name=[{0}] val=[{1}] {2}x{3}@{4},{5}" -f $name, $val, $w, $h, $x, $y))
  }
  # combos
  $cond2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ComboBox)
  $combos = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond2)
  foreach ($e in $combos) {
    $name=""; $val=""; $x=0;$y=0;$w=0;$h=0
    try { $name=$e.Current.Name } catch {}
    try { $r=$e.Current.BoundingRectangle; $x=[int]$r.X; $y=[int]$r.Y; $w=[int]$r.Width; $h=[int]$r.Height } catch {}
    try { $vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $val=$vp.Current.Value } } catch {}
    [void]$sb.AppendLine(("COMBO name=[{0}] val=[{1}] {2}x{3}@{4},{5}" -f $name, $val, $w, $h, $x, $y))
  }
  # buttons with 신청 but we only list, not click
  $cond3 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $btns = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond3)
  foreach ($e in $btns) {
    $name=""
    try { $name=$e.Current.Name } catch {}
    if ($name -match "신청|저장|상신|출장|검색|조회") {
      $r=$e.Current.BoundingRectangle
      [void]$sb.AppendLine(("BTN name=[{0}] {1}x{2}@{3},{4}" -f $name, [int]$r.Width, [int]$r.Height, [int]$r.X, [int]$r.Y))
    }
  }
  # URL
  $condE = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  foreach ($e in $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condE)) {
    $name=""; $val=""
    try { $name=$e.Current.Name } catch {}
    try { $vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $val=$vp.Current.Value } } catch {}
    if ($val -match '^https?://' -or $name -match '주소') {
      [void]$sb.AppendLine(("URL name=[{0}] val=[{1}]" -f $name, $val))
    }
  }
  $p = Join-Path $outDir ("chrome_edits_" + $Tag + ".txt")
  [System.IO.File]::WriteAllText($p, $sb.ToString(), $utf8bom)
  Write-Output ("DUMP " + $p + " len=" + $sb.Length)
}

$i=0
foreach ($line in $all) {
  if ($line -match 'h=(\d+).*cls=\[Chrome_WidgetWin_1\]') {
    $i++
    $h = [IntPtr][int64]$Matches[1]
    Dump-Edits $h ("w" + $i)
  }
}
Write-Output "DONE"