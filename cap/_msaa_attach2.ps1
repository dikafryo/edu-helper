$ErrorActionPreference = "Continue"
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

function Dump-AccFlat([object]$Root, [string]$OutPath, [int]$Max=4000) {
  $list = New-Object System.Collections.Generic.List[string]
  $q = New-Object System.Collections.Generic.Queue[object]
  $q.Enqueue(@{N=$Root; D=0})
  $n=0
  while ($q.Count -gt 0 -and $n -lt $Max) {
    $cur = $q.Dequeue(); $a=$cur.N; $d=[int]$cur.D; $n++
    if ($null -eq $a) { continue }
    $name=""; $role=""; $val=""; $state=""; $x=0;$y=0;$w=0;$h=0
    try { $name=[string]$a.accName(0) } catch {}
    try { $role=[string]$a.accRole(0) } catch {}
    try { $val=[string]$a.accValue(0) } catch {}
    try { $state=[string]$a.accState(0) } catch {}
    try { $a.accLocation([ref]$x,[ref]$y,[ref]$w,[ref]$h,0) } catch {}
    $keep = ($d -le 4) -or ($name -match "붙임|첨부|파일|다운로드|저장|목록|\.hwp|\.pdf|\.xlsx|\.docx|\.zip|\.hwpx|문서") -or ($role -match "list|table|row|column|cell|outline|push button|link|page tab|editable") -or ($w -gt 40 -and $h -gt 12 -and $name -and $name.Length -gt 1)
    if ($keep) {
      $list.Add(("d={0} role={1} name=[{2}] val=[{3}] {4}x{5}@{6},{7}" -f $d, $role, $name, $val, $w, $h, $x, $y))
    }
    if ($d -ge 12) { continue }
    $cc=0; try { $cc=[int]$a.accChildCount } catch {}
    for ($i=1; $i -le $cc; $i++) {
      try {
        $ch=$a.accChild($i)
        if ($null -eq $ch) { continue }
        if ($ch -is [int] -or $ch -is [long] -or $ch -is [int16] -or $ch -is [uint16]) { continue }
        $q.Enqueue(@{N=$ch; D=($d+1)})
      } catch {}
    }
  }
  [System.IO.File]::WriteAllText($OutPath, ($list -join "`r`n"), (New-Object System.Text.UTF8Encoding $true))
  Write-Output ("FLAT lines=" + $list.Count + " -> " + $OutPath)
}

function Probe([int]$ProcessId, [string]$Tag) {
  $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $p) { Write-Output ("GONE "+$Tag); return }
  $hwnd = $p.MainWindowHandle
  Write-Output ("PROBE "+$Tag+" hwnd="+([int64]$hwnd)+" title="+$p.MainWindowTitle)
  $acc = [PenNoticeNative]::GetAccessible($hwnd)
  Dump-AccFlat $acc ("F:\claude\01 개발 프로그램\pen도우미\cap\msaa_" + $Tag + "_main.txt")

  # find IE children via existing helper if any
  $ieList = New-Object System.Collections.Generic.List[IntPtr]
  Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class EnumIe {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  public static List<long> Found = new List<long>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    var sb = new StringBuilder(256);
    GetClassName(h, sb, 256);
    string c = sb.ToString();
    if (c == "Internet Explorer_Server" || c.IndexOf("SysListView") >= 0) Found.Add(h.ToInt64());
    return true;
  }
}
"@ -ErrorAction SilentlyContinue
  try {
    [EnumIe]::Found = New-Object "System.Collections.Generic.List[long]"
    $del = [EnumIe+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [EnumIe]::Cb($h,$lp) }
    [EnumIe]::EnumChildWindows($hwnd, $del, [IntPtr]::Zero)
    Write-Output ("CHILD_IE_LV=" + ([EnumIe]::Found -join ","))
    $ki=0
    foreach ($id in [EnumIe]::Found) {
      $ki++
      $ih = [IntPtr]$id
      try {
        $ia = [PenNoticeNative]::GetAccessible($ih)
        Dump-AccFlat $ia ("F:\claude\01 개발 프로그램\pen도우미\cap\msaa_" + $Tag + "_child" + $ki + ".txt")
      } catch { Write-Output ("CHILD_FAIL "+$_) }
    }
  } catch { Write-Output ("ENUM_FAIL "+$_) }

  # try activate 첨부 / 붙임 tabs
  foreach ($pat in @('*첨부*','*붙임*','*파일첨부*','*첨부파일*')) {
    $nodes = Find-AccNodes -Root $acc -NameLike $pat -MinW 3 -MaxNodes 1000
    Write-Output ("MATCH "+$pat+" count="+@($nodes).Count)
    foreach ($nd in @($nodes | Select-Object -First 6)) {
      $nm=""; $role=""; $w=0;$h=0;$x=0;$y=0
      try{$nm=[string]$nd.accName(0)}catch{}
      try{$role=[string]$nd.accRole(0)}catch{}
      try{$nd.accLocation([ref]$x,[ref]$y,[ref]$w,[ref]$h,0)}catch{}
      Write-Output ("  node role="+$role+" name=["+$nm+"] "+$w+"x"+$h)
    }
  }
}

Probe -ProcessId 20648 -Tag "recv"
Probe -ProcessId 64380 -Tag "card"
Write-Output "DONE"