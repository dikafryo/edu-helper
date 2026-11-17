$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TripWin {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static List<string> Lines = new List<string>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls=new StringBuilder(256); GetClassName(h,cls,256);
    var title=new StringBuilder(512); GetWindowText(h,title,512);
    string c=cls.ToString(); string t=title.ToString();
    if (c.IndexOf("Chrome")>=0 || t.IndexOf("출장")>=0 || t.IndexOf("신청")>=0 || c=="#32770" || c.IndexOf("Chrome_Widget")>=0)
      Lines.Add("h="+h.ToInt64()+" cls=["+c+"] title=["+t+"]");
    return true;
  }
}
"@
[TripWin]::Lines = New-Object 'System.Collections.Generic.List[string]'
$del=[TripWin+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TripWin]::Cb($h,$lp) }
[TripWin]::EnumWindows($del,[IntPtr]::Zero)
$wins=[TripWin]::Lines
[System.IO.File]::WriteAllText((Join-Path $outDir 'chrome_create_wins.txt'), ($wins -join "`r`n"), $utf8bom)
foreach($w in $wins){ Write-Output $w }

function Get-Url([IntPtr]$Hwnd) {
  try {
    $el=[System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
    foreach($e in $el.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)) {
      $n="";$v=""
      try{$n=$e.Current.Name}catch{}
      try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
      if($v -match '^https?://' -or $n -match '주소'){ return $v }
    }
  } catch {}
  return ""
}

function Dump-Form([IntPtr]$Hwnd, [string]$Tag) {
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $sb=New-Object System.Text.StringBuilder
  $tb=New-Object System.Text.StringBuilder 512; [TripWin]::GetWindowText($Hwnd,$tb,512)
  [void]$sb.AppendLine("HWND="+$Hwnd.ToInt64()+" title=["+$tb.ToString()+"]")
  [void]$sb.AppendLine("URL=["+(Get-Url $Hwnd)+"]")
  $keys=@('출장','신청','목적','사유','장소','출장지','관내','관외','기간','시작','종료','일시','시간','종류','차량','일수','결재','저장','상신','여비','교통','수단','숙박','일비','식비','인원','부서','공용','자가','대중','기차','버스','항공','선박','택시','지역','국내','국외','분','시','날짜','일자','부터','까지','비고','내용','제목','닫기','취소')
  foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner','Button','Document')){
    $ct=[System.Windows.Automation.ControlType]::$typeName
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
    $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
    [void]$sb.AppendLine("==== $typeName count=$($all.Count) ====")
    foreach($e in $all){
      $n="";$v="";$x=0;$y=0;$w=0;$hh=0;$auto="";$help="";$en=$true
      try{
        $n=$e.Current.Name; $auto=$e.Current.AutomationId; $help=$e.Current.HelpText; $en=$e.Current.IsEnabled
        $r=$e.Current.BoundingRectangle; $x=[int]$r.X;$y=[int]$r.Y;$w=[int]$r.Width;$hh=[int]$r.Height
      }catch{continue}
      try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
      if($w -lt 3 -or $hh -lt 3){ continue }
      if($typeName -eq 'Button'){
        $keep=$false
        foreach($k in $keys){ if(($n+$v+$auto+$help) -like ("*"+$k+"*")){ $keep=$true; break } }
        if(-not $keep){ continue }
      }
      [void]$sb.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] en={3} help=[{4}] {5}x{6}@{7},{8}" -f $n,$auto,$v,$en,$help,$w,$hh,$x,$y))
      if($typeName -eq 'ComboBox'){
        try {
          $items=$e.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
          foreach($it in $items){
            $inm=""; try{$inm=$it.Current.Name}catch{}
            if($inm){ [void]$sb.AppendLine(("  OPTION name=[{0}]" -f $inm)) }
          }
        } catch {}
        try {
          $sel=$e.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)
          if($sel){
            foreach($s in $sel.Current.GetSelection()){
              $sn=""; try{$sn=$s.Current.Name}catch{}
              [void]$sb.AppendLine(("  SELECTED name=[{0}]" -f $sn))
            }
          }
        } catch {}
      }
    }
  }
  $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
  $stack=New-Object System.Collections.Stack
  $stack.Push($root)
  $count=0; $hit=0
  [void]$sb.AppendLine("==== KEYWORD_WALK ====")
  while($stack.Count -gt 0 -and $count -lt 12000){
    $el=$stack.Pop(); $count++
    $ct="";$name="";$auto="";$val="";$x=0;$y=0;$w=0;$hh=0
    try{
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $name=$el.Current.Name; $auto=$el.Current.AutomationId
      $r=$el.Current.BoundingRectangle; $x=[int]$r.X;$y=[int]$r.Y;$w=[int]$r.Width;$hh=[int]$r.Height
    }catch{continue}
    try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$val=$vp.Current.Value}}catch{}
    $blob="$ct|$name|$auto|$val"
    $match=$false
    foreach($k in $keys){ if($blob -like ("*"+$k+"*")){ $match=$true; break } }
    if($match -and $w -gt 2 -and $hh -gt 2){
      $hit++
      [void]$sb.AppendLine(("{0}|name=[{1}] auto=[{2}] val=[{3}] {4}x{5}@{6},{7}" -f $ct,$name,$auto,$val,$w,$hh,$x,$y))
    }
    try{
      $ch=$walker.GetFirstChild($el)
      while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
    }catch{}
  }
  [void]$sb.AppendLine("WALKED=$count HITS=$hit")
  $p=Join-Path $outDir ("chrome_create_" + $Tag + ".txt")
  [System.IO.File]::WriteAllText($p,$sb.ToString(),$utf8bom)
  Write-Output ("DUMP $p bytes="+$sb.Length+" hits=$hit")
}

$i=0
$targets=@()
foreach($line in $wins){
  if($line -match 'h=(\d+)'){
    $h=[IntPtr][int64]$Matches[1]
    $title=""; if($line -match 'title=\[(.*)\]$'){ $title=$Matches[1] }
    $cls=""; if($line -match 'cls=\[([^\]]+)\]'){ $cls=$Matches[1] }
    $score=0
    if($title -match '출장'){ $score+=10 }
    if($title -match '신청'){ $score+=5 }
    if($cls -eq 'Chrome_WidgetWin_1'){ $score+=2 }
    if($title -match '4세대'){ $score+=1 }
    if($title -match '출장신청|개인출장'){ $score+=8 }
    $i = $i + 1
    $tag = "w" + $i
    $targets += [pscustomobject]@{H=$h; Tag=$tag; Score=$score; Title=$title; Cls=$cls; Line=$line}
  }
}
$targets | Sort-Object Score -Descending | ForEach-Object { Write-Output ("TARGET score=$($_.Score) $($_.Line)") }
foreach($t in ($targets | Where-Object { $_.Cls -eq 'Chrome_WidgetWin_1' -or $_.Score -ge 5 })){
  try { Dump-Form $t.H $t.Tag } catch { Write-Output ("DUMP_ERR $($t.Tag): "+$_.Exception.Message) }
}
$fg=[TripWin]::GetForegroundWindow()
$ft=New-Object System.Text.StringBuilder 512; [TripWin]::GetWindowText($fg,$ft,512)
Write-Output ("FG h="+$fg.ToInt64()+" title=["+$ft.ToString()+"] url=["+(Get-Url $fg)+"]")
Write-Output "DONE"