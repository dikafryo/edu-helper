$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
# candidate hwnds from previous scan
$cands=@(23008926, 8913692, 208149332, 12262870, 28973740, 60755800, 5642708, 1905406, 25235518, 9508152)
# also re-enum
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TW5 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int Left,Top,Right,Bottom; }
  public static List<string> Lines = new List<string>();
  public static List<long> Ids = new List<long>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    string c=cls.ToString();
    if (c.IndexOf("Chrome_Widget")<0) return true;
    RECT r; GetWindowRect(h, out r);
    int w=r.Right-r.Left; int hh=r.Bottom-r.Top;
    if (w<200 || hh<200) return true;
    if (r.Left <= -30000) return true; // minimized main
    var title=new StringBuilder(512); GetWindowText(h,title,512);
    Lines.Add(string.Format("vis={0} h={1} cls=[{2}] title=[{3}] {4}x{5}@{6},{7}", IsWindowVisible(h), h.ToInt64(), c, title.ToString(), w, hh, r.Left, r.Top));
    Ids.Add(h.ToInt64());
    return true;
  }
}
"@
[TW5]::Lines=New-Object 'System.Collections.Generic.List[string]'
[TW5]::Ids=New-Object 'System.Collections.Generic.List[long]'
$del=[TW5+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TW5]::Cb($h,$lp) }
[TW5]::EnumWindows($del,[IntPtr]::Zero)
Write-Output "=== CANDIDATES ==="
[TW5]::Lines | ForEach-Object { Write-Output $_ }

function Dump-Hid([long]$Id) {
  $Hwnd=[IntPtr]$Id
  try { $root=[System.Windows.Automation.AutomationElement]::FromHandle($Hwnd) } catch { Write-Output ("FAIL $Id"); return }
  $sb=New-Object System.Text.StringBuilder
  try {
    [void]$sb.AppendLine("HWND=$Id Name=["+$root.Current.Name+"]")
    $r=$root.Current.BoundingRectangle
    [void]$sb.AppendLine(("Bounds {0}x{1}@{2},{3}" -f [int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
  } catch {}
  # URL
  foreach($typeName in @('Edit','Document')){
    $ct=[System.Windows.Automation.ControlType]::$typeName
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
    foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)){
      try{
        $n=$e.Current.Name; $v=""; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
        if($v -match 'http|neis|\.go\.kr' -or $n -match '주소'){ [void]$sb.AppendLine("$typeName URL/name=[$n] val=[$v]") }
      }catch{}
    }
  }
  $editCount=0; $comboCount=0
  foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner','Button')){
    $ct=[System.Windows.Automation.ControlType]::$typeName
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
    $els=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
    if($typeName -eq 'Edit'){ $editCount=$els.Count }
    if($typeName -eq 'ComboBox'){ $comboCount=$els.Count }
    [void]$sb.AppendLine("==== $typeName count=$($els.Count) ====")
    foreach($e in $els){
      try{
        $n=$e.Current.Name; $auto=$e.Current.AutomationId; $en=$e.Current.IsEnabled
        $rr=$e.Current.BoundingRectangle; $w=[int]$rr.Width;$hh=[int]$rr.Height;$x=[int]$rr.X;$y=[int]$rr.Y
        if($w -lt 2 -or $hh -lt 2){continue}
        $v=""; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
        if($typeName -eq 'Button' -and $n -notmatch '신청|저장|상신|조회|추가|삭제|선택|닫기|취소|여비|교통|출장|관내|관외|확인|검색|임시|결재|첨부|등록|불러|초기'){ continue }
        [void]$sb.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] en={3} {4}x{5}@{6},{7}" -f $n,$auto,$v,$en,$w,$hh,$x,$y))
        if($typeName -eq 'ComboBox'){
          $items=$e.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
          foreach($it in $items){ $inm=""; try{$inm=$it.Current.Name}catch{}; if($inm){[void]$sb.AppendLine("  OPTION=[$inm]")} }
        }
      }catch{}
    }
  }
  # keyword labels
  $keys=@('여비','교통','숙박','일비','식비','출장지','출장목적','출장사유','관내','관외','출장종류','출장기간','공용차량','출장인원','시작','종료','사유','장소','목적','일시','수단')
  $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
  $stack=New-Object System.Collections.Stack; $stack.Push($root); $cnt=0; $hits=0
  [void]$sb.AppendLine("==== LABELS ====")
  while($stack.Count -gt 0 -and $cnt -lt 12000){
    $el=$stack.Pop(); $cnt++
    try{
      $name=$el.Current.Name
      $ch=$walker.GetFirstChild($el); while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
      if(-not $name){continue}
      $hit=$false; foreach($k in $keys){ if($name -like ("*"+$k+"*")){ $hit=$true; break } }
      if(-not $hit){continue}
      $hits++
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $rr=$el.Current.BoundingRectangle
      $v=""; try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
      [void]$sb.AppendLine(("{0}|name=[{1}] val=[{2}] {3}x{4}@{5},{6}" -f $ct,$name,$v,[int]$rr.Width,[int]$rr.Height,[int]$rr.X,[int]$rr.Y))
    }catch{}
  }
  [void]$sb.AppendLine("WALKED=$cnt HITS=$hits edits=$editCount combos=$comboCount")
  $p=Join-Path $outDir ("hidden_$Id.txt")
  [System.IO.File]::WriteAllText($p,$sb.ToString(),$utf8bom)
  Write-Output ("WROTE $p bytes="+$sb.Length+" edits=$editCount combos=$comboCount hits=$hits")
}

foreach($id in [TW5]::Ids){ Dump-Hid $id }
# also forced cands not in list
foreach($id in $cands){
  if(-not [TW5]::Ids.Contains($id)){ Dump-Hid $id }
}
Write-Output DONE