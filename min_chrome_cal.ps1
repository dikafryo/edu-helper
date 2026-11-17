Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class MinWin {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Window)
$col = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
for ($i=0; $i -lt $col.Count; $i++) {
  $w = $col.Item($i)
  try {
    $n = [string]$w.Current.Name
    $c = [string]$w.Current.ClassName
    if ($c -match 'Chrome_WidgetWin' -and $n -match 'Calendar|캘린더') {
      $hwnd = [IntPtr]$w.Current.NativeWindowHandle
      [void][MinWin]::ShowWindow($hwnd, 6) # SW_MINIMIZE
      Write-Host ("min $n")
    }
  } catch {}
}
