$ErrorActionPreference = "Continue"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param([string]$Path,$Default); if (-not (Test-Path -LiteralPath $Path)) { return $Default }; try { $raw=[System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8); if ([string]::IsNullOrWhiteSpace($raw)){return $Default}; return ($raw|ConvertFrom-Json) } catch { return $Default } }
function Write-JsonFile { param([string]$Path,$Object); $json=$Object|ConvertTo-Json -Depth 8; $u=New-Object System.Text.UTF8Encoding $true; [System.IO.File]::WriteAllText($Path,$json,$u) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

function Dump-AccTree([IntPtr]$Hwnd, [string]$OutPath, [int]$MaxDepth=8) {
  $sb = New-Object System.Text.StringBuilder
  function Walk($node, $depth, $path) {
    if ($depth -gt $MaxDepth -or $null -eq $node) { return }
    $name=""; $role=""; $val=""; $state=""
    try { $name = [string]$node.accName(0) } catch {}
    try { $role = [string]$node.accRole(0) } catch {}
    try { $val = [string]$node.accValue(0) } catch {}
    try { $state = [string]$node.accState(0) } catch {}
    $line = ("{0}[{1}] role={2} name={3} val={4} state={5}" -f ("  "*$depth), $path, $role, $name, $val, $state)
    [void]$sb.AppendLine($line)
    $kids = @()
    try {
      $ch = $node.accChildCount
      for ($i=1; $i -le [int]$ch; $i++) {
        try {
          $c = $node.accChild($i)
          if ($c -is [int] -or $c -is [int64]) { continue }
          if ($null -ne $c) { $kids += ,$c }
        } catch {}
      }
    } catch {}
    $idx=0
    foreach ($k in $kids) {
      $idx++
      Walk $k ($depth+1) ($path + "." + $idx)
      if ($sb.Length -gt 400000) { return }
    }
  }
  $root = $null
  try { $root = [PenNoticeNative]::AccessibleObjectFromWindowWrap($Hwnd) } catch {}
  if (-not $root) {
    try {
      # fallback via existing helper if any
      $root = Get-AccRoot -Hwnd $Hwnd
    } catch {}
  }
  if (-not $root) {
    # use IAccessible via oleacc
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class AccDump {
  [DllImport("oleacc.dll")]
  public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint dwId, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppvObject);
  public static object FromWindow(IntPtr hwnd) {
    Guid iid = new Guid("{618736E0-3C3D-11CF-810C-00AA003DFF94}");
    object obj;
    int hr = AccessibleObjectFromWindow(hwnd, 0, ref iid, out obj); // OBJID_WINDOW=0
    if (hr != 0) {
      hr = AccessibleObjectFromWindow(hwnd, unchecked((uint)0xFFFFFFFC), ref iid, out obj); // OBJID_CLIENT
    }
    if (hr != 0) throw new Exception("AOFW hr="+hr);
    return obj;
  }
}
"@
    $root = [AccDump]::FromWindow($Hwnd)
  }
  Walk $root 0 "0"
  [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
  Write-Output ("DUMP " + $OutPath + " len=" + $sb.Length)
}

# also UIA dump for attachment keywords
function Dump-Uia([IntPtr]$Hwnd, [string]$OutPath) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $sb = New-Object System.Text.StringBuilder
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $stack = New-Object System.Collections.Stack
  $stack.Push(@{E=$el; D=0})
  $n=0
  while ($stack.Count -gt 0 -and $n -lt 2500) {
    $cur = $stack.Pop()
    $e = $cur.E; $d = [int]$cur.D
    if ($d -gt 12) { continue }
    $n++
    $name=""; $ct=""; $val=""
    try { $name = $e.Current.Name } catch {}
    try { $ct = $e.Current.LocalizedControlType } catch {}
    try {
      $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      if ($vp) { $val = $vp.Current.Value }
    } catch {}
    $interesting = ($name -match "붙임|첨부|파일|다운로드|저장|문서관리|목록|\.hwp|\.pdf|\.hwpx|\.xlsx|\.docx|\.zip") -or ($d -le 2)
    if ($interesting -or ($name -and $name.Length -gt 0 -and $d -le 6)) {
      [void]$sb.AppendLine(("{0}{1} [{2}] val={3}" -f ("  "*$d), $ct, $name, $val))
    }
    # push children reverse
    $child = $walker.GetLastChild($e)
    $tmp = New-Object System.Collections.Generic.List[object]
    while ($null -ne $child) {
      $tmp.Add($child)
      $child = $walker.GetPreviousSibling($child)
    }
    foreach ($c in $tmp) { $stack.Push(@{E=$c; D=($d+1)}) }
  }
  [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
  Write-Output ("UIA " + $OutPath + " nodes=" + $n + " len=" + $sb.Length)
}

foreach ($pair in @(
  @{Pid=20648; Tag="recv"},
  @{Pid=64380; Tag="card"}
)) {
  $p = Get-Process -Id $pair.Pid -ErrorAction SilentlyContinue
  if (-not $p) { Write-Output ("GONE " + $pair.Tag); continue }
  $h = $p.MainWindowHandle
  Write-Output ("WIN " + $pair.Tag + " hwnd=" + [int64]$h + " title=" + $p.MainWindowTitle)
  Dump-Uia $h ("F:\claude\01 개발 프로그램\pen도우미\cap\uia_attach_" + $pair.Tag + ".txt")
}

# list top-level windows related
Get-Process | Where-Object { $_.MainWindowTitle -match "문서관리|첨부|붙임|기안|공문|수신" } | ForEach-Object {
  Write-Output ("TOP " + $_.Id + " [" + $_.MainWindowTitle + "]")
}
Write-Output "DONE"