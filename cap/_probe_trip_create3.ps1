$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TW3 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static List<long> ChromeHwnds = new List<long>();
  public static List<string> Lines = new List<string>();
  public static List<string> Kids = new List<string>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    var title=new StringBuilder(512); GetWindowText(h,title,512);
    string c=cls.ToString(); string t=title.ToString();
    Lines.Add("h="+h.ToInt64()+" cls=["+c+"] title=["+t+"]");
    if (c=="Chrome_WidgetWin_1") ChromeHwnds.Add(h.ToInt64());
    return true;
  }
  public static bool KidCb(IntPtr h, IntPtr lp) {
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    var title=new StringBuilder(256); GetWindowText(h,title,256);
    string c=cls.ToString();
    if (c.IndexOf("Chrome")>=0 || c.IndexOf("Internet")>=0 || title.Length>0)
      Kids.Add("kid h="+h.ToInt64()+" cls=["+c+"] title=["+title.ToString()+"]");
    return true;
  }
}
"@
[TW3]::Lines=New-Object 'System.Collections.Generic.List[string]'
[TW3]::ChromeHwnds=New-Object 'System.Collections.Generic.List[long]'
$del=[TW3+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TW3]::Cb($h,$lp) }
[TW3]::EnumWindows($del,[IntPtr]::Zero)
Write-Output "=== CHROME TOP ==="
foreach($id in [TW3]::ChromeHwnds){
  $line = ([TW3]::Lines | Where-Object { $_ -like ("h="+$id+" *") } | Select-Object -First 1)
  Write-Output $line
  [TW3]::Kids=New-Object 'System.Collections.Generic.List[string]'
  $kdel=[TW3+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TW3]::KidCb($h,$lp) }
  [TW3]::EnumChildWindows([IntPtr]$id, $kdel, [IntPtr]::Zero)
  foreach($k in [TW3]::Kids){ if($k -match 'Render|Internet|Widget'){ Write-Output $k } }
}

function Dump-Win([long]$Id, [string]$Tag) {
  $Hwnd=[IntPtr]$Id
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $sb=New-Object System.Text.StringBuilder
  $tb=New-Object System.Text.StringBuilder 512; [TW3]::GetWindowText($Hwnd,$tb,512)
  [void]$sb.AppendLine("HWND=$Id title=["+$tb.ToString()+"]")
  # URL
  $condE=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
  foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condE)){
    $n="";$v=""; try{$n=$e.Current.Name}catch{}; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
    if($v -match 'neis|\.go\.kr|http' -or $n -match '주소'){ [void]$sb.AppendLine("URL=[$v] name=[$n]"); break }
  }
  foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner','Document')){
    $ct=[System.Windows.Automation.ControlType]::$typeName
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
    $els=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
    [void]$sb.AppendLine("==== $typeName count=$($els.Count) ====")
    foreach($e in $els){
      try{
        $n=$e.Current.Name; $auto=$e.Current.AutomationId; $en=$e.Current.IsEnabled
        $r=$e.Current.BoundingRectangle; $w=[int]$r.Width;$hh=[int]$r.Height;$x=[int]$r.X;$y=[int]$r.Y
        if($w -lt 3 -or $hh -lt 3){continue}
        $v=""; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
        [void]$sb.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] en={3} {4}x{5}@{6},{7}" -f $n,$auto,$v,$en,$w,$hh,$x,$y))
        if($typeName -eq 'ComboBox'){
          foreach($scope in @([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.TreeScope]::Descendants)){
            $items=$e.FindAll($scope,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
            foreach($it in $items){ $inm=""; try{$inm=$it.Current.Name}catch{}; if($inm){[void]$sb.AppendLine("  OPTION=[$inm]")} }
            if($items.Count -gt 0){ break }
          }
        }
      }catch{}
    }
  }
  # relevant buttons
  $condB=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
  [void]$sb.AppendLine("==== BTNS ====")
  foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condB)){
    try{
      $n=$e.Current.Name
      if($n -match '신청|저장|상신|조회|추가|삭제|선택|닫기|취소|여비|교통|출장|관내|관외|확인|불러|검색|임시|결재|첨부'){
        $r=$e.Current.BoundingRectangle
        [void]$sb.AppendLine(("BTN name=[{0}] {1}x{2}@{3},{4}" -f $n,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
      }
    }catch{}
  }
  # tabs
  $condT=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)
  [void]$sb.AppendLine("==== TABS ====")
  foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condT)){
    try{ $n=$e.Current.Name; $r=$e.Current.BoundingRectangle; [void]$sb.AppendLine(("TAB name=[{0}] {1}x{2}@{3},{4}" -f $n,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y)) }catch{}
  }
  # labels
  $keys=@('여비','교통수단','교통','숙박','일비','식비','출장지','출장목적','출장사유','관내','관외','출장종류','출장기간','시작','종료','공용차량','출장인원','일시','사유','장소','목적')
  $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
  $stack=New-Object System.Collections.Stack; $stack.Push($root); $cnt=0
  [void]$sb.AppendLine("==== LABELS ====")
  while($stack.Count -gt 0 -and $cnt -lt 15000){
    $el=$stack.Pop(); $cnt++
    try{
      $name=$el.Current.Name
      $ch=$walker.GetFirstChild($el); while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
      if(-not $name){ continue }
      $hit=$false; foreach($k in $keys){ if($name -like ("*"+$k+"*")){ $hit=$true; break } }
      if(-not $hit){ continue }
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $r=$el.Current.BoundingRectangle
      $val=""; try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$val=$vp.Current.Value}}catch{}
      [void]$sb.AppendLine(("{0}|name=[{1}] val=[{2}] {3}x{4}@{5},{6}" -f $ct,$name,$val,[int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
    }catch{}
  }
  $p=Join-Path $outDir ("create_dump_" + $Tag + ".txt")
  [System.IO.File]::WriteAllText($p,$sb.ToString(),$utf8bom)
  Write-Output ("WROTE $p bytes="+$sb.Length)
}

$idx=0
foreach($id in [TW3]::ChromeHwnds){
  $idx++
  Dump-Win $id ("c"+$idx)
}
# Also dump FG if different
$fg=[TW3]::GetForegroundWindow()
Write-Output ("FG="+$fg.ToInt64())
if(-not [TW3]::ChromeHwnds.Contains($fg.ToInt64())){
  $cls=New-Object System.Text.StringBuilder 256; [TW3]::GetClassName($fg,$cls,256)
  Write-Output ("FG_CLS="+$cls.ToString())
  try { Dump-Win $fg.ToInt64() "fg" } catch { Write-Output ("FG dump fail: "+$_) }
}
Write-Output DONE