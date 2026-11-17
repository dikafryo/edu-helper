$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TripWin2 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static List<string> Lines = new List<string>();
  public static List<string> ChildLines = new List<string>();
  public static IntPtr Parent;
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    var title=new StringBuilder(512); GetWindowText(h,title,512);
    Lines.Add("h="+h.ToInt64()+" cls=["+cls.ToString()+"] title=["+title.ToString()+"]");
    return true;
  }
  public static bool ChildCb(IntPtr h, IntPtr lp) {
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    var title=new StringBuilder(512); GetWindowText(h,title,512);
    string c=cls.ToString(); string t=title.ToString();
    if (t.Length>0 || c.IndexOf("Chrome")>=0 || c.IndexOf("Internet")>=0 || c=="Chrome_RenderWidgetHostHWND" || c.IndexOf("Widget")>=0)
      ChildLines.Add("  child h="+h.ToInt64()+" cls=["+c+"] title=["+t+"]");
    return true;
  }
}
"@

# Enum ALL visible top-level with any title
[TripWin2]::Lines = New-Object 'System.Collections.Generic.List[string]'
$del=[TripWin2+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TripWin2]::Cb($h,$lp) }
[TripWin2]::EnumWindows($del,[IntPtr]::Zero)
$all=[TripWin2]::Lines
# filter interesting
$interesting = $all | Where-Object { $_ -match 'Chrome|출장|신청|메시지|Alert|Dialog|#32770|WidgetWin|네이|neis|팝업|새 창' }
[System.IO.File]::WriteAllText((Join-Path $outDir 'all_interesting_wins.txt'), ($interesting -join "`r`n"), $utf8bom)
Write-Output "=== INTERESTING WINS ==="
$interesting | ForEach-Object { Write-Output $_ }

# dump 웹 페이지 메시지 dialog deeply
$msgHwnd = [IntPtr]::Zero
foreach($line in $all){
  if($line -match '웹 페이지 메시지' -and $line -match 'h=(\d+)'){ $msgHwnd=[IntPtr][int64]$Matches[1]; break }
}
if($msgHwnd -ne [IntPtr]::Zero){
  Write-Output ("MSG_HWND="+$msgHwnd.ToInt64())
  [TripWin2]::ChildLines = New-Object 'System.Collections.Generic.List[string]'
  [TripWin2]::Parent = $msgHwnd
  $cdel=[TripWin2+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TripWin2]::ChildCb($h,$lp) }
  [TripWin2]::EnumChildWindows($msgHwnd, $cdel, [IntPtr]::Zero)
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($msgHwnd)
  $sb=New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("MSG_DIALOG")
  $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
  $stack=New-Object System.Collections.Stack; $stack.Push($root); $n=0
  while($stack.Count -gt 0 -and $n -lt 500){
    $el=$stack.Pop(); $n++
    try{
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $name=$el.Current.Name; $auto=$el.Current.AutomationId
      $r=$el.Current.BoundingRectangle
      $val=""
      try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$val=$vp.Current.Value}}catch{}
      [void]$sb.AppendLine(("{0}|name=[{1}] auto=[{2}] val=[{3}] {4}x{5}@{6},{7}" -f $ct,$name,$auto,$val,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
      $ch=$walker.GetFirstChild($el)
      while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
    }catch{}
  }
  [void]$sb.AppendLine("NATIVE_CHILDREN:")
  foreach($c in [TripWin2]::ChildLines){ [void]$sb.AppendLine($c) }
  [System.IO.File]::WriteAllText((Join-Path $outDir 'chrome_msg_dialog.txt'), $sb.ToString(), $utf8bom)
  Write-Output ("MSG dump bytes="+$sb.Length)
  Write-Output $sb.ToString().Substring(0, [Math]::Min(2000,$sb.Length))
}

# Deep dump main NEIS chrome focusing on NEW form fields (여비/교통/목적 edits)
$neis=[IntPtr]1705744
# re-resolve by title
foreach($line in $all){
  if($line -match '4세대 나이스' -and $line -match 'h=(\d+)' -and $line -match 'Chrome_WidgetWin_1'){ $neis=[IntPtr][int64]$Matches[1]; break }
}
Write-Output ("NEIS_HWND="+$neis.ToInt64())
$root=[System.Windows.Automation.AutomationElement]::FromHandle($neis)
$sb2=New-Object System.Text.StringBuilder
# URL
$condE=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
$url=""
foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condE)){
  $n="";$v=""; try{$n=$e.Current.Name}catch{}; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
  if($v -match 'neis|http' -or $n -match '주소'){ $url=$v; break }
}
[void]$sb2.AppendLine("URL=[$url]")
# ALL edits/combos/radios/checks with full detail
foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner','Document','Slider')){
  $ct=[System.Windows.Automation.ControlType]::$typeName
  $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
  $els=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
  [void]$sb2.AppendLine("==== $typeName count=$($els.Count) ====")
  foreach($e in $els){
    try{
      $n=$e.Current.Name; $auto=$e.Current.AutomationId; $help=$e.Current.HelpText; $en=$e.Current.IsEnabled
      $r=$e.Current.BoundingRectangle; $w=[int]$r.Width;$hh=[int]$r.Height;$x=[int]$r.X;$y=[int]$r.Y
      if($w -lt 3 -or $hh -lt 3){continue}
      $v=""; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
      # skip chrome address only if duplicate later
      [void]$sb2.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] en={3} {4}x{5}@{6},{7}" -f $n,$auto,$v,$en,$w,$hh,$x,$y))
      if($typeName -eq 'ComboBox'){
        $items=$e.FindAll([System.Windows.Automation.TreeScope]::Children,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
        if($items.Count -eq 0){
          $items=$e.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
        }
        foreach($it in $items){ $inm=""; try{$inm=$it.Current.Name}catch{}; if($inm){[void]$sb2.AppendLine("  OPTION=[$inm]")} }
      }
    }catch{}
  }
}
# buttons with trip keywords
$condB=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
[void]$sb2.AppendLine("==== RELEVANT_BUTTONS ====")
foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condB)){
  try{
    $n=$e.Current.Name
    if($n -match '신청|저장|상신|조회|검색|추가|삭제|선택|닫기|취소|여비|교통|출장|관내|관외|확인|불러'){
      $r=$e.Current.BoundingRectangle
      [void]$sb2.AppendLine(("BTN name=[{0}] {1}x{2}@{3},{4}" -f $n,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
    }
  }catch{}
}
# tabs
$condT=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)
[void]$sb2.AppendLine("==== TABS ====")
foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condT)){
  try{
    $n=$e.Current.Name; $r=$e.Current.BoundingRectangle
    [void]$sb2.AppendLine(("TAB name=[{0}] {1}x{2}@{3},{4}" -f $n,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
  }catch{}
}
# keyword text labels
$keys=@('여비','교통','수단','숙박','일비','식비','출장지','출장목적','출장사유','관내','관외','출장종류','출장기간','시작일시','종료일시','공용차량','인원')
$walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
$stack=New-Object System.Collections.Stack; $stack.Push($root); $cnt=0
[void]$sb2.AppendLine("==== LABELS ====")
while($stack.Count -gt 0 -and $cnt -lt 15000){
  $el=$stack.Pop(); $cnt++
  try{
    $name=$el.Current.Name; if(-not $name){ 
      $ch=$walker.GetFirstChild($el); while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }; continue
    }
    $hit=$false; foreach($k in $keys){ if($name -like ("*"+$k+"*")){ $hit=$true; break } }
    if($hit){
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $r=$el.Current.BoundingRectangle
      $val=""; try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$val=$vp.Current.Value}}catch{}
      [void]$sb2.AppendLine(("{0}|name=[{1}] val=[{2}] {3}x{4}@{5},{6}" -f $ct,$name,$val,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
    }
    $ch=$walker.GetFirstChild($el); while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
  }catch{}
}
$p=Join-Path $outDir 'chrome_create_form_deep.txt'
[System.IO.File]::WriteAllText($p,$sb2.ToString(),$utf8bom)
Write-Output ("DEEP bytes="+$sb2.Length)
# print first part
$txt=$sb2.ToString()
Write-Output $txt.Substring(0, [Math]::Min(4500, $txt.Length))
Write-Output "DONE"