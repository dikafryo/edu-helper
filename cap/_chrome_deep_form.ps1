$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
}
"@
$h=[Fg]::GetForegroundWindow()
$tb=New-Object System.Text.StringBuilder 512; [Fg]::GetWindowText($h,$tb,512)
$root=[System.Windows.Automation.AutomationElement]::FromHandle($h)
$sb=New-Object System.Text.StringBuilder
[void]$sb.AppendLine("FG="+ $h.ToInt64() +" title=["+ $tb.ToString() +"]")

# address bar
$condE=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
foreach($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condE)){
  $n="";$v=""
  try{$n=$e.Current.Name}catch{}
  try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
  if($v -match '^https?://' -or $n -match '주소'){ [void]$sb.AppendLine("URL=["+$v+"] name=["+$n+"]"); break }
}

# keywords of interest
$keys=@('출장','신청','목적','사유','장소','출장지','관내','관외','기간','시작','종료','일시','시간','종류','차량','일수','결재','저장','상신','검색','조회','부서','인원')
$interestingTypes=@('Edit','ComboBox','CheckBox','RadioButton','Button','Text','Document','DataItem','HeaderItem','TabItem','Hyperlink','ListItem','Spinner','Calendar','Custom','Group','Table','DataGrid')

$walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
$stack=New-Object System.Collections.Stack
$stack.Push($root)
$count=0; $hit=0
while($stack.Count -gt 0 -and $count -lt 8000){
  $el=$stack.Pop(); $count++
  $ct=""; $name=""; $auto=""; $help=""; $val=""; $x=0;$y=0;$w=0;$hh=0;$en=$true
  try{
    $ct=$el.Current.ControlType.ProgrammaticName
    if($ct){$ct=$ct.Replace('ControlType.','')}
    $name=$el.Current.Name
    $auto=$el.Current.AutomationId
    $help=$el.Current.HelpText
    $en=$el.Current.IsEnabled
    $r=$el.Current.BoundingRectangle; $x=[int]$r.X; $y=[int]$r.Y; $w=[int]$r.Width; $hh=[int]$r.Height
  } catch { continue }
  try{ $vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$val=$vp.Current.Value} }catch{}
  $blob=("$ct|$name|$auto|$help|$val")
  $match=$false
  foreach($k in $keys){ if($blob -like ("*"+$k+"*")){ $match=$true; break } }
  $typeOk=$false
  foreach($t in $interestingTypes){ if($ct -eq $t){ $typeOk=$true; break } }
  if($match -or ($typeOk -and $name -ne '' -and $w -gt 5 -and $hh -gt 5 -and $y -gt 150 -and $y -lt 1100)){
    if($match -or ($ct -in @('Edit','ComboBox','CheckBox','RadioButton','Button','Spinner','TabItem') -and $name -ne '')){
      $hit++
      [void]$sb.AppendLine(("{0}|name=[{1}] auto=[{2}] val=[{3}] en={4} {5}x{6}@{7},{8}" -f $ct,$name,$auto,$val,$en,$w,$hh,$x,$y))
    }
  }
  try{
    $ch=$walker.GetFirstChild($el)
    while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
  }catch{}
}
[void]$sb.AppendLine("WALKED=$count HITS=$hit")
$p=Join-Path $outDir 'chrome_trip_fields_2.txt'
[System.IO.File]::WriteAllText($p,$sb.ToString(),$utf8bom)
Write-Output ("wrote $p bytes=" + $sb.Length + " hits=$hit walked=$count")
# also dump pure edits/combos/radios regardless of keyword
$sb2=New-Object System.Text.StringBuilder
foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner')){
  $ct=[System.Windows.Automation.ControlType]::$typeName
  $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
  [void]$sb2.AppendLine("==== $typeName count=$($all.Count) ====")
  foreach($e in $all){
    $n="";$v="";$x=0;$y=0;$w=0;$hh=0;$auto=""
    try{$n=$e.Current.Name; $auto=$e.Current.AutomationId; $r=$e.Current.BoundingRectangle; $x=[int]$r.X;$y=[int]$r.Y;$w=[int]$r.Width;$hh=[int]$r.Height}catch{}
    try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
    if($w -lt 5 -or $hh -lt 5){ continue }
    [void]$sb2.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] {3}x{4}@{5},{6}" -f $n,$auto,$v,$w,$hh,$x,$y))
  }
}
$p2=Join-Path $outDir 'chrome_trip_inputs_2.txt'
[System.IO.File]::WriteAllText($p2,$sb2.ToString(),$utf8bom)
Write-Output ("wrote $p2 bytes=" + $sb2.Length)