$ErrorActionPreference='Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Window)
$col = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Host ("windows={0}" -f $col.Count)
for ($i=0; $i -lt $col.Count; $i++) {
  $w = $col.Item($i)
  try {
    $n = [string]$w.Current.Name
    $c = [string]$w.Current.ClassName
    if ($c -match 'Chrome|Calendar|Pen|도우미' -or $n -match 'Chrome|캘린더|Calendar|Google|PEN') {
      Write-Host ("[{0}] cls={1} name={2}" -f $i, $c, $n)
    }
  } catch {}
}
