$ErrorActionPreference="Continue"
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$utf8bom=New-Object System.Text.UTF8Encoding $true
$outDir="F:\claude\01 개발 프로그램\pen도우미\cap"
# dump each known render widget
$ids=@(17047412, 2296678, 86774708, 1705744)
function Dump-One([long]$Id) {
  $Hwnd=[IntPtr]$Id
  try { $root=[System.Windows.Automation.AutomationElement]::FromHandle($Hwnd) } catch { Write-Output ("FAIL FromHandle $Id"); return }
  $sb=New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("HWND=$Id")
  try {
    [void]$sb.AppendLine(("Name=["+$root.Current.Name+"] Ct="+$root.Current.ControlType.ProgrammaticName))
    $r=$root.Current.BoundingRectangle
    [void]$sb.AppendLine(("Bounds {0}x{1}@{2},{3}" -f [int]$r.Width,[int]$r.Height,[int]$r.X,[int]$r.Y))
  } catch {}
  foreach($typeName in @('Edit','ComboBox','CheckBox','RadioButton','Spinner','Document','Button','Text','Custom','Group','Pane','Window','DataGrid')){
    try {
      $ct=[System.Windows.Automation.ControlType]::$typeName
      $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,$ct)
      $els=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
      if($els.Count -eq 0){ continue }
      [void]$sb.AppendLine("==== $typeName count=$($els.Count) ====")
      $shown=0
      foreach($e in $els){
        try{
          $n=$e.Current.Name; $auto=$e.Current.AutomationId; $en=$e.Current.IsEnabled
          $rr=$e.Current.BoundingRectangle; $w=[int]$rr.Width;$hh=[int]$rr.Height;$x=[int]$rr.X;$y=[int]$rr.Y
          if($w -lt 2 -or $hh -lt 2){continue}
          $v=""; try{$vp=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
          if($typeName -eq 'Button' -and $n -notmatch '신청|저장|상신|조회|추가|삭제|선택|닫기|취소|여비|교통|출장|관내|관외|확인|불러|검색|임시|결재|첨부|확인|취소'){ continue }
          if($typeName -eq 'Text' -and $n -notmatch '출장|여비|교통|관내|관외|목적|사유|장소|기간|시작|종료|종류|인원|일시|수단|숙박|일비|식비'){ continue }
          if($typeName -eq 'Pane' -or $typeName -eq 'Group' -or $typeName -eq 'Custom'){
            if($n -notmatch '출장|여비|교통|신청|목적|사유|관내|관외'){ continue }
          }
          [void]$sb.AppendLine(("$typeName name=[{0}] auto=[{1}] val=[{2}] en={3} {4}x{5}@{6},{7}" -f $n,$auto,$v,$en,$w,$hh,$x,$y))
          $shown++
          if($typeName -eq 'ComboBox'){
            $items=$e.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
            foreach($it in $items){ $inm=""; try{$inm=$it.Current.Name}catch{}; if($inm){[void]$sb.AppendLine("  OPTION=[$inm]")} }
          }
          if($shown -gt 200){ [void]$sb.AppendLine("...truncated"); break }
        }catch{}
      }
    } catch { [void]$sb.AppendLine("ERR $typeName "+$_.Exception.Message) }
  }
  # full keyword walk
  $keys=@('여비','교통','숙박','일비','식비','출장지','출장목적','출장사유','관내','관외','출장종류','출장기간','공용차량','출장인원','시작일시','종료일시','신청','저장','상신')
  $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
  $stack=New-Object System.Collections.Stack; $stack.Push($root); $cnt=0; $hits=0
  [void]$sb.AppendLine("==== RAW_KEYWORD ====")
  while($stack.Count -gt 0 -and $cnt -lt 20000){
    $el=$stack.Pop(); $cnt++
    try{
      $name=$el.Current.Name; $auto=$el.Current.AutomationId
      $ch=$walker.GetFirstChild($el); while($null -ne $ch){ $stack.Push($ch); $ch=$walker.GetNextSibling($ch) }
      $blob="$name|$auto"
      $hit=$false; foreach($k in $keys){ if($blob -like ("*"+$k+"*")){ $hit=$true; break } }
      if(-not $hit){ continue }
      $hits++
      $ct=$el.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
      $rr=$el.Current.BoundingRectangle
      $v=""; try{$vp=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if($vp){$v=$vp.Current.Value}}catch{}
      [void]$sb.AppendLine(("{0}|name=[{1}] auto=[{2}] val=[{3}] {4}x{5}@{6},{7}" -f $ct,$name,$auto,$v,[int]$rr.Width,[int]$rr.Height,[int]$rr.X,[int]$rr.Y))
    }catch{}
  }
  [void]$sb.AppendLine("RAW_WALKED=$cnt HITS=$hits")
  $p=Join-Path $outDir ("render_$Id.txt")
  [System.IO.File]::WriteAllText($p,$sb.ToString(),$utf8bom)
  Write-Output ("WROTE $p bytes="+$sb.Length+" hits=$hits walked=$cnt")
}
foreach($id in $ids){ Dump-One $id }
Write-Output DONE