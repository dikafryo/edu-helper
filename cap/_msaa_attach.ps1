$ErrorActionPreference = "Continue"
$script:DataDir = Join-Path $env:LOCALAPPDATA "PenHelper"
function Read-JsonFile { param([string]$Path,$Default); if (-not (Test-Path -LiteralPath $Path)) { return $Default }; try { $raw=[System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8); if ([string]::IsNullOrWhiteSpace($raw)){return $Default}; return ($raw|ConvertFrom-Json) } catch { return $Default } }
function Write-JsonFile { param([string]$Path,$Object); $json=$Object|ConvertTo-Json -Depth 8; $u=New-Object System.Text.UTF8Encoding $true; [System.IO.File]::WriteAllText($Path,$json,$u) }
. "F:\claude\01 개발 프로그램\pen도우미\PenNotice.ps1"

function Get-AccFromHwnd([IntPtr]$Hwnd) {
  return [PenNoticeNative]::GetAccessible($Hwnd)
}

function Dump-AccFlat([object]$Root, [string]$OutPath, [int]$Max=3000) {
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
    $hit = $false
    if ($name -match "붙임|첨부|파일|다운로드|저장|목록|\.|hwp|pdf|xlsx|docx|zip|hwpx|문서관리|카드") { $hit=$true }
    if ($role -match "list|table|row|column|cell|outline|push button|link|page tab" -or $role -in @("34","33","28","29","30","42","43","9","10","11")) { $hit=$true }
    if ($d -le 3 -or $hit -or ($w -gt 20 -and $h -gt 10 -and $name)) {
      $list.Add(("{0}d={1} role={2} name=[{3}] val=[{4}] {5}x{6}@{7},{8} st={9}" -f ("  "*[Math]::Min($d,8)), $d, $role, $name, $val, $w, $h, $x, $y, $state))
    }
    if ($d -ge 10) { continue }
    $cc=0; try { $cc=[int]$a.accChildCount } catch {}
    for ($i=1; $i -le $cc; $i++) {
      try {
        $ch=$a.accChild($i)
        if ($null -eq $ch) { continue }
        if ($ch -is [int] -or $ch -is [long] -or $ch -is [int16]) { continue }
        $q.Enqueue(@{N=$ch; D=($d+1)})
      } catch {}
    }
  }
  [System.IO.File]::WriteAllText($OutPath, ($list -join "`r`n"), (New-Object System.Text.UTF8Encoding $true))
  Write-Output ("FLAT " + $OutPath + " lines=" + $list.Count)
}

# Enum child IE_Server / SysListView32
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class EnumKids {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static List<string> Lines = new List<string>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    var cls = new StringBuilder(256); GetClassName(h, cls, 256);
    var title = new StringBuilder(256); GetWindowText(h, title, 256);
    RECT r; GetWindowRect(h, out r);
    int w=r.R-r.L, ht=r.B-r.T;
    bool vis = IsWindowVisible(h);
    string c = cls.ToString();
    if (c.IndexOf("Internet Explorer_Server")>=0 || c.IndexOf("SysListView")>=0 || c.IndexOf("ListView")>=0 || c.IndexOf("ATL:")>=0 || title.Length>0 || (vis && w>50 && ht>30)) {
      Lines.Add(string.Format("h=0x{0:X} vis={1} {2}x{3} cls=[{4}] title=[{5}]", h.ToInt64(), vis, w, ht, c, title));
    }
    return true;
  }
}
"@

function Probe([int]$Pid, [string]$Tag) {
  $p = Get-Process -Id $Pid -ErrorAction SilentlyContinue
  if (-not $p) { Write-Output ("GONE "+$Tag); return }
  $hwnd = $p.MainWindowHandle
  Write-Output ("PROBE "+$Tag+" hwnd="+([int64]$hwnd)+" title="+$p.MainWindowTitle)
  [EnumKids]::Lines = New-Object "System.Collections.Generic.List[string]"
  $del = [EnumKids+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [EnumKids]::Cb($h,$lp) }
  [EnumKids]::EnumChildWindows($hwnd, $del, [IntPtr]::Zero)
  $childPath = "F:\claude\01 개발 프로그램\pen도우미\cap\child_" + $Tag + ".txt"
  [System.IO.File]::WriteAllText($childPath, ([EnumKids]::Lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $true))
  Write-Output ("CHILD " + $childPath + " n=" + [EnumKids]::Lines.Count)

  # Acc on main and each IE_Server
  $acc = [PenNoticeNative]::GetAccessible($hwnd)
  Dump-AccFlat $acc ("F:\claude\01 개발 프로그램\pen도우미\cap\msaa_" + $Tag + "_main.txt")
  foreach ($line in [EnumKids]::Lines) {
    if ($line -match "Internet Explorer_Server") {
      if ($line -match "h=0x([0-9A-Fa-f]+)") {
        $ih = [IntPtr]([Convert]::ToInt64($Matches[1], 16))
        Write-Output ("IE " + $Tag + " " + $ih)
        try {
          $ia = [PenNoticeNative]::GetAccessible($ih)
          Dump-AccFlat $ia ("F:\claude\01 개발 프로그램\pen도우미\cap\msaa_" + $Tag + "_ie.txt") 4000
        } catch { Write-Output ("IE_ACC_FAIL " + $_) }
      }
    }
    if ($line -match "SysListView") {
      if ($line -match "h=0x([0-9A-Fa-f]+)") {
        $lh = [IntPtr]([Convert]::ToInt64($Matches[1], 16))
        Write-Output ("LV " + $Tag + " " + $lh)
        try {
          $la = [PenNoticeNative]::GetAccessible($lh)
          Dump-AccFlat $la ("F:\claude\01 개발 프로그램\pen도우미\cap\msaa_" + $Tag + "_lv.txt") 1000
        } catch { Write-Output ("LV_FAIL " + $_) }
      }
    }
  }

  # try click tabs with 첨부/붙임/파일
  $tabs = Find-AccNodes -Root $acc -NameLike "*첨부*" -MinW 5 -MaxNodes 800
  $tabs2 = Find-AccNodes -Root $acc -NameLike "*붙임*" -MinW 5 -MaxNodes 800
  $tabs3 = Find-AccNodes -Root $acc -NameLike "*파일*" -MinW 5 -MaxNodes 800
  Write-Output ("TAB_첨부=" + @($tabs).Count + " 붙임=" + @($tabs2).Count + " 파일=" + @($tabs3).Count)
  foreach ($t in (@($tabs)+@($tabs2)+@($tabs3) | Select-Object -First 8)) {
    $nm=""; try{$nm=[string]$t.accName(0)}catch{}
    Write-Output ("TABCAND ["+$nm+"]")
  }
}

Probe 20648 "recv"
Probe 64380 "card"
Write-Output "DONE"