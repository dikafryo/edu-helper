# PenNotice.ps1 — 안내공문/마스킹/MSAA helpers (dot-sourced by PenHelper.ps1)
#Requires -Version 5.1

$script:NoticeWin32 = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class PenNoticeNative {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  public static bool ForceForeground(IntPtr hWnd) {
    IntPtr fg = GetForegroundWindow();
    uint cur = GetCurrentThreadId();
    uint dummy;
    uint fgTid = GetWindowThreadProcessId(fg, out dummy);
    uint targetTid = GetWindowThreadProcessId(hWnd, out dummy);
    bool attachedFg = false;
    bool attachedTg = false;
    if (fgTid != 0 && fgTid != cur) attachedFg = AttachThreadInput(cur, fgTid, true);
    if (targetTid != 0 && targetTid != cur && targetTid != fgTid) attachedTg = AttachThreadInput(cur, targetTid, true);
    ShowWindow(hWnd, 9);
    BringWindowToTop(hWnd);
    SetForegroundWindow(hWnd);
    if (attachedTg) AttachThreadInput(cur, targetTid, false);
    if (attachedFg) AttachThreadInput(cur, fgTid, false);
    return GetForegroundWindow() == hWnd;
  }
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint dwObjectID, ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppvObject);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, StringBuilder lParam);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Auto, SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
  public const uint WM_NULL = 0;
  public const uint SMTO_ABORTIFHUNG = 0x0002;
  public const uint SMTO_NORMAL = 0x0000;
  public const uint SMTO_BLOCK = 0x0001;
  public const int LVM_FIRST = 0x1000;
  public const int LVM_GETITEMCOUNT = LVM_FIRST + 4;
  public const int LVM_GETITEMTEXTW = LVM_FIRST + 115;
  public static System.Collections.Generic.List<IntPtr> FindChildrenByClass(IntPtr parent, string className) {
    var list = new System.Collections.Generic.List<IntPtr>();
    EnumProc cb = (h, lp) => {
      var sb = new StringBuilder(256);
      GetClassName(h, sb, 256);
      if (string.Equals(sb.ToString(), className, StringComparison.OrdinalIgnoreCase) || sb.ToString().IndexOf(className, StringComparison.OrdinalIgnoreCase) >= 0)
        list.Add(h);
      return true;
    };
    EnumChildWindows(parent, cb, IntPtr.Zero);
    return list;
  }
  public const uint OBJID_CLIENT = 0xFFFFFFFC;
  public static readonly Guid IID_IAccessible = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
  public static object GetAcc(IntPtr hwnd) {
    object acc; Guid g = IID_IAccessible;
    int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref g, out acc);
    if (hr != 0) throw new Exception("AccessibleObjectFromWindow hr=" + hr);
    return acc;
  }
  public static IntPtr FindChildByClass(IntPtr parent, string className) {
    IntPtr found = IntPtr.Zero;
    EnumProc cb = (h, lp) => {
      var sb = new StringBuilder(256);
      GetClassName(h, sb, 256);
      if (sb.ToString() == className) { found = h; return false; }
      return true;
    };
    EnumChildWindows(parent, cb, IntPtr.Zero);
    return found;
  }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'PenNoticeNative').Type) {
  try { Add-Type -TypeDefinition $script:NoticeWin32 -Language CSharp } catch { }
}


function Wait-ForWindowResponsive {
  <#
    .SYNOPSIS
      기안창이 응답할 때까지 대기. hung면 SendMessage 안 보내고 폴링만.
  #>
  param(
    [IntPtr]$Hwnd,
    [int]$TimeoutMs = 8000,
    [int]$PollMs = 400,
    [int]$ProbeMs = 500
  )
  if ($Hwnd -eq [IntPtr]::Zero) {
    return [pscustomobject]@{ Ok = $false; Reason = 'no-hwnd'; WaitedMs = 0; Hung = $false }
  }
  try {
    if (-not [PenNoticeNative]::IsWindow($Hwnd)) {
      return [pscustomobject]@{ Ok = $false; Reason = 'not-a-window'; WaitedMs = 0; Hung = $false }
    }
  } catch { }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $lastHung = $false
  while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
    $hung = $false
    try { $hung = [PenNoticeNative]::IsHungAppWindow($Hwnd) } catch { $hung = $false }
    $lastHung = $hung
    if ($hung) {
      # never hammer a hung window — sleep only
      Start-Sleep -Milliseconds $PollMs
      continue
    }
    $remain = $TimeoutMs - [int]$sw.ElapsedMilliseconds
    if ($remain -le 0) { break }
    $slice = [Math]::Min($ProbeMs, [Math]::Max(50, $remain))
    $result = [IntPtr]::Zero
    $okPtr = [IntPtr]::Zero
    try {
      $okPtr = [PenNoticeNative]::SendMessageTimeout(
        $Hwnd,
        [PenNoticeNative]::WM_NULL,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        [PenNoticeNative]::SMTO_ABORTIFHUNG,
        [uint32]$slice,
        [ref]$result)
    } catch {
      Start-Sleep -Milliseconds $PollMs
      continue
    }
    if ($okPtr -ne [IntPtr]::Zero) {
      return [pscustomobject]@{
        Ok = $true
        Reason = 'ok'
        WaitedMs = [int]$sw.ElapsedMilliseconds
        Hung = $false
      }
    }
    Start-Sleep -Milliseconds $PollMs
  }
  return [pscustomobject]@{
    Ok = $false
    Reason = 'timeout'
    WaitedMs = [int][Math]::Min($TimeoutMs, $sw.ElapsedMilliseconds)
    Hung = $lastHung
  }
}



# Fallback JSON helpers if host has not defined them yet
if (-not (Get-Command Read-JsonFile -ErrorAction SilentlyContinue)) {
  function Read-JsonFile {
    param([string]$Path, $Default)
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    try {
      $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
      if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
      return ($raw | ConvertFrom-Json)
    } catch { return $Default }
  }
}
if (-not (Get-Command Write-JsonFile -ErrorAction SilentlyContinue)) {
  function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 8
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $json, $utf8bom)
  }
}

if (-not $script:DataDir) { $script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper' }
$script:SettingsPath = Join-Path $script:DataDir 'settings.json'
$script:MaskMapDir = Join-Path $script:DataDir 'maskmaps'
$script:OutboxDir = 'F:\claude\01 개발 프로그램\pen도우미\outbox'
foreach ($d in @($script:MaskMapDir, $script:OutboxDir)) {
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$script:DefaultSettings = [ordered]@{
  ApprovalPresets = @('개인결재선')
  RecipientPresets = @('기본수신')
  KeywordMap = @()
  LastApprovalPreset = ''
  LastRecipientPreset = ''
  GrokPromptHeader = '안내공문으로 바꿔줘'
  TightenLetterSpacing = $true
  CharsPerLine = 40
  SpillCharLimit = 5
  MaxTightenSteps = 6
  BodyFillInTable = $false
  ApplyBodyFont = $true
  BodyFontName = '굴림'
  BodyFontSize = 12
}

function Get-PenSettings {
  $data = Read-JsonFile -Path $script:SettingsPath -Default $null
  $s = [ordered]@{}
  foreach ($k in $script:DefaultSettings.Keys) { $s[$k] = $script:DefaultSettings[$k] }
  if ($null -ne $data) {
    foreach ($p in $data.PSObject.Properties) { $s[$p.Name] = $p.Value }
  }
  if ($null -eq $s.ApprovalPresets) { $s.ApprovalPresets = @('개인결재선') }
  if ($s.ApprovalPresets -isnot [System.Array]) { $s.ApprovalPresets = @($s.ApprovalPresets) }
  if ($null -eq $s.RecipientPresets) { $s.RecipientPresets = @('기본수신') }
  if ($s.RecipientPresets -isnot [System.Array]) { $s.RecipientPresets = @($s.RecipientPresets) }
  if ($null -eq $s.KeywordMap) { $s.KeywordMap = @() }
  if ($s.KeywordMap -isnot [System.Array]) { $s.KeywordMap = @($s.KeywordMap) }
  return $s
}

function Save-PenSettings {
  param($Settings)
  Write-JsonFile -Path $script:SettingsPath -Object $Settings
}

$script:Settings = Get-PenSettings
$script:NoticeSourceTitle = ''
$script:NoticeSourceBody = ''
$script:NoticeDraft = ''
$script:NoticeMasked = ''
$script:LastMaskPairs = @()
$script:LastMaskMapPath = ''
$script:WxsCache = @()

function Get-WxsWindows {
  $list = @()
  Get-Process -Name 'WXSClient' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -eq 0) { return }
    $title = [string]$_.MainWindowTitle
    if ([string]::IsNullOrWhiteSpace($title)) { return }
    $kind = 'received'
    if ($title -like '표준서식*') { $kind = 'template' }
    elseif ($title -like '문서관리카드*') { $kind = 'card' }
    $list += [pscustomobject]@{
      Pid = $_.Id; Title = $title; Hwnd = [IntPtr]$_.MainWindowHandle; Kind = $kind
      Display = '[{0}] {1}' -f $kind, $title
    }
  }
  return @($list)
}

function Invoke-ActivateWindow {
  param([IntPtr]$Hwnd)
  if ($Hwnd -eq [IntPtr]::Zero) { return $false }
  try {
    [void][PenNoticeNative]::ShowWindow($Hwnd, 9)
    try { [void][PenNoticeNative]::ForceForeground($Hwnd) } catch {
      [void][PenNoticeNative]::SetForegroundWindow($Hwnd)
    }
    Start-Sleep -Milliseconds 250
    return $true
  } catch { return $false }
}

function Get-IeAccFromHwnd {
  param([IntPtr]$Hwnd)
  $ie = [PenNoticeNative]::FindChildByClass($Hwnd, 'Internet Explorer_Server')
  if ($ie -eq [IntPtr]::Zero) { return $null }
  try { return [PenNoticeNative]::GetAcc($ie) } catch { return $null }
}

function Find-AccNodes {
  param($Root, [string]$NameExact, [string]$NameLike, [int]$MinW = 0, [int]$MaxNodes = 1200)
  $found = New-Object System.Collections.Generic.List[object]
  if ($null -eq $Root) { return @() }
  $stack = New-Object System.Collections.Generic.Stack[object]
  $stack.Push(@{ A = $Root; Id = 0 })
  $n = 0
  while ($stack.Count -gt 0 -and $n -lt $MaxNodes) {
    $it = $stack.Pop(); $a = $it.A; $id = [int]$it.Id
    if ($null -eq $a) { continue }
    $n++
    $nm = $null; try { $nm = [string]$a.accName($id) } catch { }
    $ok = $false
    if ($NameExact -and $nm -eq $NameExact) { $ok = $true }
    if ($NameLike -and $nm -like $NameLike) { $ok = $true }
    if ($ok) {
      $role = $null; try { $role = [string]$a.accRole($id) } catch { }
      $val = $null; try { $val = [string]$a.accValue($id) } catch { }
      $act = $null; try { $act = [string]$a.accDefaultAction($id) } catch { }
      $x = 0; $y = 0; $w = 0; $h = 0
      try { $a.accLocation([ref]$x, [ref]$y, [ref]$w, [ref]$h, $id) } catch { }
      if ($w -ge $MinW) {
        [void]$found.Add([pscustomobject]@{
          Name = $nm; Role = $role; Value = $val; Action = $act
          X = $x; Y = $y; W = $w; H = $h; Acc = $a; Id = $id
        })
      }
    }
    if ($id -ne 0) { continue }
    $cc = 0; try { $cc = [int]$a.accChildCount } catch { }
    for ($i = $cc; $i -ge 1; $i--) {
      try {
        $ch = $null; try { $ch = $a.accChild($i) } catch { }
        if ($null -eq $ch) { $stack.Push(@{ A = $a; Id = $i }) }
        else { $stack.Push(@{ A = $ch; Id = 0 }) }
      } catch { }
    }
  }
  if (@($found).Count -eq 0) { return ,@() }
  # COM(IAccessible) 포함 시 @($list) 가 Argument types do not match 날 수 있어 ToArray 사용
  return ,$found.ToArray()
}

function Test-BlockedAccName {
  param([string]$Name)
  foreach ($b in @('결재올림', '발송', '상신', '재발송', '추가재발송')) {
    if ($Name -like ("*{0}*" -f $b)) { return $true }
  }
  return $false
}

function Invoke-AccDefault {
  param($Node)
  if ($null -eq $Node) { return $false }
  if (Test-BlockedAccName -Name $Node.Name) { throw ("차단된 동작: {0}" -f $Node.Name) }
  try {
    $Node.Acc.accDoDefaultAction($Node.Id)
    Start-Sleep -Milliseconds 400
    return $true
  } catch {
    return $false
  }
}

function Set-AccEditValue {
  param($Node, [string]$Text)
  if ($null -eq $Node) { return $false }
  try {
    try { $Node.Acc.accSelect(1, $Node.Id) } catch { }
    try {
      $Node.Acc.accDoDefaultAction($Node.Id)
    } catch { }
    Start-Sleep -Milliseconds 150
    try {
      $Node.Acc.accValue($Node.Id) = $Text
      $now = $null; try { $now = [string]$Node.Acc.accValue($Node.Id) } catch { }
      if ($now -eq $Text) { return $true }
    } catch { }
    [System.Windows.Forms.Clipboard]::SetText($Text)
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 150
    return $true
  } catch { return $false }
}

function Copy-TextFromHwpWindow {
  param([IntPtr]$Hwnd)
  if (-not (Invoke-ActivateWindow -Hwnd $Hwnd)) { return '' }
  # 1) 포털 '본문복사' 버튼이 있으면 MSAA로 클릭 (SendKeys 회피)
  try {
    $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
    if ($acc) {
      $btns = Find-AccNodes -Root $acc -NameLike '*본문복사*' -MinW 5 -MaxNodes 600
      $btn = @($btns | Where-Object { $_.Action -eq '점프' -or [string]$_.Role -eq '30' } | Select-Object -First 1)
      if (@($btn).Count -gt 0) {
        try { [System.Windows.Forms.Clipboard]::Clear() } catch { }
        Invoke-AccDefault -Node $btn[0] | Out-Null
        Start-Sleep -Milliseconds 500
        $viaBtn = ''
        try { $viaBtn = [System.Windows.Forms.Clipboard]::GetText() } catch { }
        if (-not [string]::IsNullOrWhiteSpace($viaBtn) -and $viaBtn.Length -gt 20) { return $viaBtn }
      }
    }
  } catch { }
  $hwp = [PenNoticeNative]::FindChildByClass($Hwnd, 'HwpMainEditWnd')
  if ($hwp -ne [IntPtr]::Zero) {
    [void][PenNoticeNative]::ForceForeground($Hwnd)
    try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
    Start-Sleep -Milliseconds 200
  }
  try { [System.Windows.Forms.Clipboard]::Clear() } catch { }
  try {
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 120
    [System.Windows.Forms.SendKeys]::SendWait('^c')
    Start-Sleep -Milliseconds 280
  } catch {
    return ''
  }
  $txt = ''
  try { $txt = [System.Windows.Forms.Clipboard]::GetText() } catch { }
  return $txt
}

function Paste-TextToHwpWindow {
  param([IntPtr]$Hwnd, [string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return $false }
  if (-not (Invoke-ActivateWindow -Hwnd $Hwnd)) { return $false }
  try {
    $hwp = [PenNoticeNative]::FindChildByClass($Hwnd, 'HwpMainEditWnd')
    if ($hwp -ne [IntPtr]::Zero) {
      [void][PenNoticeNative]::SetForegroundWindow($Hwnd)
      try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
      Start-Sleep -Milliseconds 180
    }
    [System.Windows.Forms.Clipboard]::SetText($Text)
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 220
    return $true
  } catch { return $false }
}

function Get-HwpBodyHwnd {
  param([IntPtr]$Hwnd)
  if ($Hwnd -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
  return [PenNoticeNative]::FindChildByClass($Hwnd, 'HwpMainEditWnd')
}

function Get-IeServerHwnd {
  param([IntPtr]$Hwnd)
  if ($Hwnd -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
  return [PenNoticeNative]::FindChildByClass($Hwnd, 'Internet Explorer_Server')
}

function Find-NoticeTitleEditNode {
  param([IntPtr]$Hwnd)
  # 제목: 기안 WXSClient > Internet Explorer_Server > MSAA role 42 (editable text) Name=제목
  # 문서정보(결재정보) 영역의 한 줄 입력칸. HwpMainEditWnd 아님.
  $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
  if ($null -eq $acc) { return $null }
  $nodes = Find-AccNodes -Root $acc -NameExact '제목' -MinW 0 -MaxNodes 1200
  $edits = @($nodes | Where-Object {
    ([string]$_.Role -eq '42') -and ([int]$_.W -ge 120) -and ([int]$_.H -gt 0) -and ([int]$_.H -le 80)
  } | Sort-Object { - [int]$_.W })
  if (@($edits).Count -gt 0) { return $edits[0] }
  $edits2 = @($nodes | Where-Object { [string]$_.Role -eq '42' -and [int]$_.W -ge 80 } | Sort-Object { -[int]$_.W })
  if (@($edits2).Count -gt 0) { return $edits2[0] }
  return $null
}

function Find-NoticeBodyTabNode {
  param([IntPtr]$Hwnd)
  # 본문 탭: IE_Server MSAA Name=본문, Action=점프 (role 30/34)
  $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
  if ($null -eq $acc) { return $null }
  $tabs = Find-AccNodes -Root $acc -NameExact '본문' -MinW 10 -MaxNodes 800
  $tab = @($tabs | Where-Object { $_.Action -eq '점프' -or [string]$_.Role -eq '30' -or [string]$_.Role -eq '34' } | Sort-Object { -[int]$_.W } | Select-Object -First 1)
  if (@($tab).Count -gt 0) { return $tab[0] }
  return ($tabs | Select-Object -First 1)
}

function Find-NoticeDocInfoTabNode {
  param([IntPtr]$Hwnd)
  # 제목 입력을 위해 결재정보/문서정보 쪽 탭
  $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
  if ($null -eq $acc) { return $null }
  foreach ($name in @('결재정보', '문서정보')) {
    $nodes = Find-AccNodes -Root $acc -NameLike ($name + '*') -MinW 20 -MaxNodes 800
    $tab = @($nodes | Where-Object { $_.Action -eq '점프' -or [string]$_.Role -eq '30' -or [string]$_.Role -eq '34' } | Select-Object -First 1)
    if (@($tab).Count -gt 0) { return $tab[0] }
  }
  return $null
}

function Split-NoticeBodyItems {
  param([string]$Body)
  # 줄 단위로 번호/가나다/붙임 항목 분리. 빈 줄은 유지.
  $lines = @($Body -split "`r?`n")
  $items = New-Object System.Collections.ArrayList
  foreach ($ln in $lines) {
    if ($null -eq $ln) { continue }
    [void]$items.Add([string]$ln)
  }
  return ,$items.ToArray()
}

function Test-NoticeNumberedPrefix {
  param([string]$Line)
  # "1. ", "12. ", "가. ", "나. ", "붙임  1. " 등
  if ($Line -match '^\s*(\d+)\.\s+\S') { return $true }
  if ($Line -match '^\s*([가-힣])\.\s+\S') { return $true }
  if ($Line -match '^\s*붙임\s+\d+\.\s+\S') { return $true }
  return $false
}

function Get-NoticePrefixAndRest {
  param([string]$Line)
  # 내어쓰기 적용 대상: 번호/기호 + 공백까지를 prefix, 나머지를 rest
  $m = [regex]::Match($Line, '^(?<pre>\s*(?:붙임\s+)?(?:\d+|[가-힣])\.\s+)(?<rest>.*)$')
  if ($m.Success) {
    return [pscustomobject]@{ Prefix = $m.Groups['pre'].Value; Rest = $m.Groups['rest'].Value; Numbered = $true }
  }
  return [pscustomobject]@{ Prefix = ''; Rest = $Line; Numbered = $false }
}

function Send-HangulOutdentKeys {
  param([switch]$InTable)
  # 한글 기안기: 줄바뀜 정렬(내어쓰기) — 일반 Alt+Tab, 표 안 Alt+Shift+Tab
  Start-Sleep -Milliseconds 60
  if ($InTable) {
    [System.Windows.Forms.SendKeys]::SendWait('%+{TAB}')
  } else {
    [System.Windows.Forms.SendKeys]::SendWait('%{TAB}')
  }
  Start-Sleep -Milliseconds 80
}

function Paste-TextChunk {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return }
  [System.Windows.Forms.Clipboard]::SetText($Text)
  Start-Sleep -Milliseconds 40
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 70
}

function Get-NoticeDisplayWidth {
  param([string]$S)
  # 대략치: 한글·전각 1, ASCII 0.5 → 정수로 반올림. UIA 줄정보 없을 때 추정용.
  if ([string]::IsNullOrEmpty($S)) { return 0 }
  $w = 0.0
  foreach ($ch in $S.ToCharArray()) {
    $code = [int]$ch
    if ($code -le 0x7F) { $w += 0.5 }
    else { $w += 1.0 }
  }
  return [int][Math]::Ceiling($w)
}

function Test-NoticeSmallSpill {
  param([string]$Line, [int]$CharsPerLine = 40, [int]$SpillLimit = 5)
  $w = Get-NoticeDisplayWidth -S $Line
  if ($w -le $CharsPerLine) { return $false }
  $spill = $w - $CharsPerLine
  return ($spill -ge 1 -and $spill -le $SpillLimit)
}

function Send-HangulTightenLetterSpacing {
  param([int]$Times = 1)
  # 한글: 자간 줄이기 Alt+Shift+N (반복)
  for ($i = 0; $i -lt $Times; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait('%+n')
    Start-Sleep -Milliseconds 40
  }
}

function Send-HangulSqueezeParagraph {
  # 한글: 단락을 한 줄로 맞춤/압축에 가까운 단축키 Alt+Shift+J
  [System.Windows.Forms.SendKeys]::SendWait('%+j')
  Start-Sleep -Milliseconds 80
}

function Invoke-NoticeParagraphTighten {
  param(
    [string]$Line,
    [int]$CharsPerLine = 40,
    [int]$SpillLimit = 5,
    [int]$MaxSteps = 6
  )
  if (-not (Test-NoticeSmallSpill -Line $Line -CharsPerLine $CharsPerLine -SpillLimit $SpillLimit)) {
    return 0
  }
  $spill = (Get-NoticeDisplayWidth -S $Line) - $CharsPerLine
  $steps = [Math]::Min($MaxSteps, [Math]::Max(1, $spill))
  # 방금 입력한 줄/단락 선택 (줄 끝 → Shift+Home)
  [System.Windows.Forms.SendKeys]::SendWait('+{HOME}')
  Start-Sleep -Milliseconds 60
  # 5자 이하 넘침: Alt+Shift+J 우선, 실패/부족 시 Alt+Shift+N 반복
  Send-HangulSqueezeParagraph
  Send-HangulTightenLetterSpacing -Times $steps
  [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}')
  Start-Sleep -Milliseconds 40
  return $steps
}

function Apply-HangulBodyFont {
  <#
    .SYNOPSIS
      한글기안기 HwpMainEditWnd 선택 범위에 글자모양 적용. 기본 굴림 12pt.
      Alt+L(글자 모양) best-effort. 글꼴명은 클립보드 붙여넣기.
    .NOTES
      반드시 HWP 포커스 후에만 호출. IE 제목칸 포커스 상태면 호출하지 말 것.
      대화상자 미확인 시 Esc로 취소. settings: ApplyBodyFont, BodyFontName, BodyFontSize.
  #>
  param(
    [IntPtr]$Hwnd,
    [string]$FontName = '굴림',
    [int]$FontSize = 12,
    [switch]$SelectAll
  )
  if ([string]::IsNullOrWhiteSpace($FontName)) { $FontName = '굴림' }
  if ($FontSize -lt 8 -or $FontSize -gt 72) { $FontSize = 12 }
  if (-not (Invoke-ActivateWindow -Hwnd $Hwnd)) { return $false }
  $hwp = Get-HwpBodyHwnd -Hwnd $Hwnd
  if ($hwp -eq [IntPtr]::Zero) { return $false }
  [void][PenNoticeNative]::ForceForeground($Hwnd)
  try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
  Start-Sleep -Milliseconds 220
  # 포그라운드가 기안창인지 확인
  $fg = [PenNoticeNative]::GetForegroundWindow()
  if ($fg -ne $Hwnd) {
    [void][PenNoticeNative]::ForceForeground($Hwnd)
    try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
    Start-Sleep -Milliseconds 200
  }
  try {
    if ($SelectAll) {
      [System.Windows.Forms.SendKeys]::SendWait('^a')
      Start-Sleep -Milliseconds 120
    }
    [System.Windows.Forms.Clipboard]::SetText($FontName)
    Start-Sleep -Milliseconds 30
    [System.Windows.Forms.SendKeys]::SendWait('%l')
    Start-Sleep -Milliseconds 450
    # 대화상자가 떴다고 가정하고 글꼴 붙여넣기
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 40
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.SendKeys]::SendWait([string]$FontSize)
    Start-Sleep -Milliseconds 60
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 180
    try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
    [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}')
    return $true
  } catch {
    try { [System.Windows.Forms.SendKeys]::SendWait('{ESC}') } catch { }
    return $false
  }
}

function Format-PasteNoticeBodyToHwp {
  <#
    .SYNOPSIS
      안내공문 본문을 한글기안기(HwpMainEditWnd)에 항목별로 붙여넣음.
      1) '1. '/'가. ' 직후 내어쓰기(Alt+Tab, 표 안 Alt+Shift+Tab)
      2) (옵션) 줄바꿈 시 5글자 이하만 넘어가면 단락 선택 후 Alt+Shift+J(한 줄 맞춤) 우선, 부족 시 Alt+Shift+N 반복
      단락 스타일·줄간격은 변경하지 않음. (옵션) 삽입 후 글자모양 굴림 12pt(설정 BodyFontName/Size).
    .NOTES
      한계: HWP UIA 줄정보가 빈약해 넘침은 CharsPerLine 추정(기본 40).
      실제 글꼴·용지·들여쓰기에 따라 오차 있음. MaxTightenSteps 초과 N 반복 안 함. J는 1회 우선 적용.
  #>
  param(
    [IntPtr]$Hwnd,
    [string]$Body,
    [switch]$InTable,
    [switch]$ClearFirst,
    [switch]$TightenLetterSpacing,
    [int]$CharsPerLine = 40,
    [int]$SpillCharLimit = 5,
    [int]$MaxTightenSteps = 6,
    [switch]$ApplyBodyFont,
    [string]$BodyFontName = '굴림',
    [int]$BodyFontSize = 12,
    [string]$TitleToRestore = ''
  )
  if ([string]::IsNullOrEmpty($Body)) { return $false }
  $wait = Wait-ForWindowResponsive -Hwnd $Hwnd -TimeoutMs 8000
  if (-not $wait.Ok) {
    return [pscustomobject]@{ Ok = $false; Reason = ('window-' + $wait.Reason); WaitedMs = $wait.WaitedMs; Hung = $wait.Hung; TightenSteps = 0; Lines = 0; FontApplied = $false }
  }
  if (-not (Invoke-ActivateWindow -Hwnd $Hwnd)) { return $false }
  # re-check after activate — still never hammer if it hung again
  $wait2 = Wait-ForWindowResponsive -Hwnd $Hwnd -TimeoutMs 4000
  if (-not $wait2.Ok) {
    return [pscustomobject]@{ Ok = $false; Reason = ('window-' + $wait2.Reason); WaitedMs = ($wait.WaitedMs + $wait2.WaitedMs); Hung = $wait2.Hung; TightenSteps = 0; Lines = 0; FontApplied = $false }
  }
  $hwp = Get-HwpBodyHwnd -Hwnd $Hwnd
  if ($hwp -eq [IntPtr]::Zero) { return $false }
  [void][PenNoticeNative]::SetForegroundWindow($Hwnd)
  try { [void][PenNoticeNative]::SetFocus($hwp) } catch { }
  Start-Sleep -Milliseconds 200

  if ($ClearFirst) {
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
    Start-Sleep -Milliseconds 80
  }

  $lines = Split-NoticeBodyItems -Body $Body
  $i = 0
  $tightenTotal = 0
  foreach ($ln in $lines) {
    $i++
    $parsed = Get-NoticePrefixAndRest -Line $ln
    if ($parsed.Numbered -and -not [string]::IsNullOrWhiteSpace($parsed.Rest)) {
      Paste-TextChunk -Text $parsed.Prefix
      Send-HangulOutdentKeys -InTable:$InTable
      Paste-TextChunk -Text $parsed.Rest
    } else {
      if ($ln.Length -gt 0) { Paste-TextChunk -Text $ln }
    }
    if ($TightenLetterSpacing -and $ln.Length -gt 0) {
      $tightenTotal += (Invoke-NoticeParagraphTighten -Line $ln -CharsPerLine $CharsPerLine -SpillLimit $SpillCharLimit -MaxSteps $MaxTightenSteps)
    }
    if ($i -lt $lines.Count) {
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Start-Sleep -Milliseconds 50
    }
  }
  $fontOk = $false
  if ($ApplyBodyFont) {
    $waitFont = Wait-ForWindowResponsive -Hwnd $Hwnd -TimeoutMs 5000
    if ($waitFont.Ok) {
      $bodyTab2 = Find-NoticeBodyTabNode -Hwnd $Hwnd
      if ($bodyTab2) { try { Invoke-AccDefault -Node $bodyTab2 | Out-Null } catch {}; Start-Sleep -Milliseconds 300 }
      $fontOk = Apply-HangulBodyFont -Hwnd $Hwnd -FontName $BodyFontName -FontSize $BodyFontSize -SelectAll
    }
  }
  # 글꼴 단축키가 제목칸을 건드린 경우 복구
  if (-not [string]::IsNullOrWhiteSpace($TitleToRestore)) {
    try {
      $docTab2 = Find-NoticeDocInfoTabNode -Hwnd $Hwnd
      if ($docTab2) { Invoke-AccDefault -Node $docTab2 | Out-Null; Start-Sleep -Milliseconds 250 }
      $te = Find-NoticeTitleEditNode -Hwnd $Hwnd
      if ($te) { Set-AccEditValue -Node $te -Text $TitleToRestore | Out-Null }
    } catch { }
  }
  return [pscustomobject]@{ Ok = $true; TightenSteps = $tightenTotal; Lines = $lines.Count; FontApplied = $fontOk; FontName = $BodyFontName; FontSize = $BodyFontSize }
}


function Get-FileNameWithoutExtSafe {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
  $n = $Name.Trim()
  $n = $n -replace '^\d+\.\s*', ''
  $n = $n -replace '\s+1부\.?\s*$', ''
  $n = $n.Trim()
  try {
    $bn = [System.IO.Path]::GetFileName($n)
    if ($bn) { $n = $bn }
    $ext = [System.IO.Path]::GetExtension($n)
    if ($ext) { return [System.IO.Path]::GetFileNameWithoutExtension($n) }
  } catch { }
  return $n
}

function Format-NoticeAttachBodyEnding {
  param([string[]]$Names)
  $clean = @()
  foreach ($raw in @($Names)) {
    $base = Get-FileNameWithoutExtSafe -Name $raw
    if ($base) { $clean += $base }
  }
  if (@($clean).Count -eq 0) { return '붙임  (원문 첨부 확인) 1부.  끝.' }
  if (@($clean).Count -eq 1) {
    return ('붙임  {0} 1부.  끝.' -f $clean[0])
  }
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt @($clean).Count; $i++) {
    $num = $i + 1
    if ($i -eq 0) {
      [void]$sb.AppendLine(('붙임  {0}. {1} 1부.' -f $num, $clean[$i]))
    } elseif ($i -eq @($clean).Count - 1) {
      [void]$sb.Append(('      {0}. {1} 1부.  끝.' -f $num, $clean[$i]))
    } else {
      [void]$sb.AppendLine(('      {0}. {1} 1부.' -f $num, $clean[$i]))
    }
  }
  return $sb.ToString()
}

function Get-ListViewItemTexts {
  param([IntPtr]$ListHwnd, [int]$Max = 40)
  $result = New-Object System.Collections.Generic.List[string]
  if ($ListHwnd -eq [IntPtr]::Zero) { return @() }
  try {
    $count = [int][PenNoticeNative]::SendMessage($ListHwnd, [PenNoticeNative]::LVM_GETITEMCOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
  } catch { $count = 0 }
  if ($count -le 0) { return @() }
  if ($count -gt $Max) { $count = $Max }
  # LVM_GETITEMTEXT needs LVITEM in remote process — often fails cross-process without ReadProcessMemory.
  # Best-effort: use MSAA on the list hwnd instead.
  try {
    $acc = [PenNoticeNative]::GetAcc($ListHwnd)
    $nodes = Find-AccNodes -Root $acc -NameLike '*' -MinW 0 -MaxNodes 800
    foreach ($nd in @($nodes)) {
      $nm = [string]$nd.Name
      if ([string]::IsNullOrWhiteSpace($nm)) { continue }
      if ($nm -match '\.(hwp|hwpx|pdf|xlsx?|docx?|pptx?|zip|jpg|png|gif|txt)$') {
        [void]$result.Add($nm.Trim())
      } elseif ($nm -match '.+\.\w{2,5}$' -and $nm -notmatch '^(이름|파일|크기|유형|수정)') {
        [void]$result.Add($nm.Trim())
      }
    }
  } catch { }
  if (@($result).Count -eq 0) {
    # still report count for caller
    return ,@("[[LISTVIEW_COUNT:$count]]")
  }
  return ,$result.ToArray()
}

function Get-NoticeAttachmentNames {
  param([IntPtr]$Hwnd, [string]$BodyText = '')
  $names = New-Object System.Collections.Generic.List[string]
  $source = 'none'
  if ($Hwnd -ne [IntPtr]::Zero) {
    try { [void](Invoke-ActivateWindow -Hwnd $Hwnd) } catch { }
    $accRoot = $null
    try { $accRoot = [PenNoticeNative]::GetAcc($Hwnd) } catch { }
    $ie = Get-IeAccFromHwnd -Hwnd $Hwnd
    foreach ($root in @($ie, $accRoot)) {
      if ($null -eq $root) { continue }
      foreach ($pat in @('*첨부파일*','*첨부 파일*','*붙임*','*첨부*')) {
        $tabs = Find-AccNodes -Root $root -NameLike $pat -MinW 3 -MaxNodes 900
        foreach ($t in @($tabs)) {
          if (Test-BlockedAccName -Name $t.Name) { continue }
          try { Invoke-AccDefault -Node $t | Out-Null; Start-Sleep -Milliseconds 350 } catch { }
        }
      }
    }
    # refresh roots after tab click
    try { $accRoot = [PenNoticeNative]::GetAcc($Hwnd) } catch { }
    $ie = Get-IeAccFromHwnd -Hwnd $Hwnd
    foreach ($root in @($ie, $accRoot)) {
      if ($null -eq $root) { continue }
      $nodes = Find-AccNodes -Root $root -NameLike '*' -MinW 0 -MaxNodes 2000
      foreach ($nd in @($nodes)) {
        $nm = [string]$nd.Name
        if ([string]::IsNullOrWhiteSpace($nm)) { continue }
        if ($nm -match '\.(hwp|hwpx|pdf|xlsx?|docx?|pptx?|zip|jpg|jpeg|png|gif|txt)$') {
          if (-not ($names -contains $nm.Trim())) { [void]$names.Add($nm.Trim()) }
        }
      }
      if (@($names).Count -gt 0) { $source = 'msaa'; break }
    }
    if (@($names).Count -eq 0) {
      try {
        $lvs = [PenNoticeNative]::FindChildrenByClass($Hwnd, 'SysListView32')
        foreach ($lv in @($lvs)) {
          $items = @(Get-ListViewItemTexts -ListHwnd $lv)
          foreach ($it in $items) {
            if ($it -like '[[LISTVIEW_COUNT:*') { continue }
            if ($it -and -not ($names -contains $it)) { [void]$names.Add($it) }
          }
        }
        if (@($names).Count -gt 0) { $source = 'listview' }
      } catch { }
    }
  }
  if (@($names).Count -eq 0 -and $BodyText) {
    foreach ($line in ($BodyText -split "`r?`n")) {
      $t = $line.Trim()
      if ($t -match '붙임\s+(?:\d+\.\s*)?(.+?)\s*1부') {
        $n = $Matches[1].Trim()
        if ($n -and $n -notmatch '원문 첨부' -and -not ($names -contains $n)) { [void]$names.Add($n) }
      } elseif ($t -match '\.(hwp|hwpx|pdf|xlsx?|docx?|zip)\b') {
        if ($t -match '([^\s\\/]+\.(?:hwp|hwpx|pdf|xlsx?|docx?|pptx?|zip))') {
          $n = $Matches[1]
          if (-not ($names -contains $n)) { [void]$names.Add($n) }
        }
      }
    }
    if (@($names).Count -gt 0) { $source = 'body' }
  }
  return [pscustomobject]@{
    Count = @($names).Count
    Names = @($names.ToArray())
    Source = $source
    Ending = (Format-NoticeAttachBodyEnding -Names @($names.ToArray()))
  }
}

function Save-NoticeAttachmentsLocal {
  param(
    [IntPtr]$Hwnd,
    [string[]]$Names,
    [string]$RootDir = 'F:\claude\01 개발 프로그램\pen도우미\attach'
  )
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $dir = Join-Path $RootDir $stamp
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $renamed = New-Object System.Collections.Generic.List[string]
  $saved = New-Object System.Collections.Generic.List[string]
  $single = (@($Names).Count -eq 1)
  $i = 0
  foreach ($raw in @($Names)) {
    $i++
    $base = [System.IO.Path]::GetFileName($raw)
    if (-not $base) { $base = $raw }
    $prefix = if ($single) { '(붙임) ' } else { ('(붙임{0}) ' -f $i) }
    $destName = $prefix + $base
    # If raw is already a bare title without extension, keep .hwp guess only as placeholder note
    $dest = Join-Path $dir $destName
    [void]$renamed.Add($destName)
    # Best-effort: if a local Downloads copy exists with same name, copy it
    $copied = $false
    foreach ($candRoot in @(
      (Join-Path $env:USERPROFILE 'Downloads'),
      (Join-Path $env:USERPROFILE 'Desktop'),
      'C:\Users\user\Downloads'
    )) {
      if (-not (Test-Path -LiteralPath $candRoot)) { continue }
      $src = Join-Path $candRoot $base
      if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $dest -Force
        [void]$saved.Add($dest)
        $copied = $true
        break
      }
    }
    if (-not $copied) {
      # placeholder sidecar so the rename list is visible even without DRM download
      $note = Join-Path $dir ($destName + '.url.txt')
      $txt = @(
        'PenHelper attachment placeholder',
        ('Original: {0}' -f $raw),
        ('Renamed: {0}' -f $destName),
        'Download via portal/WebDRM was not automated.'
      ) -join "`r`n"
      $utf8bom = New-Object System.Text.UTF8Encoding $true
      [System.IO.File]::WriteAllText($note, $txt, $utf8bom)
    }
  }
  # Try UI download click (best-effort, may need WebDRM)
  $downloadAttempted = $false
  $downloadNote = ''
  if ($Hwnd -ne [IntPtr]::Zero) {
    try {
      $acc = Get-IeAccFromHwnd -Hwnd $Hwnd
      if (-not $acc) { $acc = [PenNoticeNative]::GetAcc($Hwnd) }
      $btns = Find-AccNodes -Root $acc -NameLike '*다운로드*' -MinW 5 -MaxNodes 800
      if (@($btns).Count -eq 0) { $btns = Find-AccNodes -Root $acc -NameLike '*저장*' -MinW 5 -MaxNodes 800 }
      foreach ($b in @($btns | Select-Object -First 3)) {
        if (Test-BlockedAccName -Name $b.Name) { continue }
        if ($b.Name -match '임시저장|자동저장|결재') { continue }
        $downloadAttempted = $true
        try { Invoke-AccDefault -Node $b | Out-Null } catch { }
        Start-Sleep -Milliseconds 400
      }
      if ($downloadAttempted) {
        $downloadNote = '다운로드/저장 버튼 클릭 시도함. WebDRM·포털 저장창이면 수동 필요.'
      } else {
        $downloadNote = '다운로드 버튼을 MSAA로 찾지 못함. WebDRM/포털 첨부 저장은 자동화 불가 가능.'
      }
    } catch {
      $downloadNote = '첨부 다운로드 UI 접근 실패: ' + $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    Dir = $dir
    Renamed = @($renamed.ToArray())
    SavedPaths = @($saved.ToArray())
    DownloadAttempted = $downloadAttempted
    Note = $downloadNote
  }
}

function Invoke-NoticeAttachFilesToDraft {
  param(
    [IntPtr]$DraftHwnd,
    [string[]]$FilePaths,
    [switch]$DryRun
  )
  # Automate draft 첨부 area + OpenFileDialog. Blocked: 결재올림/발송/상신.
  if ($DryRun) {
    return [pscustomobject]@{
      Ok = $false
      DryRun = $true
      Message = '드라이런: 첨부 파일 대화상자 자동화는 구현만 하고 실행하지 않음.'
      Files = @($FilePaths)
    }
  }
  if ($DraftHwnd -eq [IntPtr]::Zero) { return [pscustomobject]@{ Ok = $false; Message = '기안창 없음' } }
  if (-not $FilePaths -or @($FilePaths).Count -eq 0) { return [pscustomobject]@{ Ok = $false; Message = '파일 없음' } }
  Invoke-ActivateWindow -Hwnd $DraftHwnd | Out-Null
  $acc = Get-IeAccFromHwnd -Hwnd $DraftHwnd
  if (-not $acc) { try { $acc = [PenNoticeNative]::GetAcc($DraftHwnd) } catch { } }
  $btn = $null
  foreach ($pat in @('*첨부파일*','*파일첨부*','*첨부*추가*','*첨부*')) {
    $cands = Find-AccNodes -Root $acc -NameLike $pat -MinW 5 -MaxNodes 1000
    foreach ($c in @($cands)) {
      if (Test-BlockedAccName -Name $c.Name) { continue }
      if ($c.Name -match '결재|발송|상신') { continue }
      $btn = $c; break
    }
    if ($btn) { break }
  }
  if (-not $btn) {
    return [pscustomobject]@{ Ok = $false; Message = '기안창에서 첨부 버튼을 찾지 못함' }
  }
  Invoke-AccDefault -Node $btn | Out-Null
  Start-Sleep -Milliseconds 800
  # OpenFileDialog: paste path list and Enter (first file); multi-select via clipboard path
  $existing = @($FilePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
  if (@($existing).Count -eq 0) {
    return [pscustomobject]@{ Ok = $false; Message = '실제 저장된 첨부 파일이 없어 대화상자에 넣을 수 없음' }
  }
  $join = ($existing -join '" "')
  $clip = '"{0}"' -f $join
  try { [System.Windows.Forms.Clipboard]::SetText($clip) } catch { }
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 500
  return [pscustomobject]@{ Ok = $true; Message = '첨부 대화상자 입력 시도 완료'; Files = $existing }
}


function New-SchoolNoticeDraft {
  param([string]$Title, [string]$Body, [string[]]$AttachmentNames = @())
  $subject = if ($Title) { $Title.Trim() } else { '안내' }
  if ($subject -notmatch '안내\s*$' -and $subject -notmatch '협조\s*$') {
    $subject = ($subject -replace '\s*협조\s*$', '').Trim() + ' 안내'
  }
  $org = ''; $docNo = ''; $docDate = ''
  if ($Body -match '([가-힣A-Za-z0-9·\s]{2,40})[-–—](\d{2,6})\((\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.?\)') {
    $org = $Matches[1].Trim(); $docNo = $Matches[2]
    $docDate = '{0}. {1}. {2}.' -f $Matches[3], [int]$Matches[4], [int]$Matches[5]
  } elseif ($Body -match '넘김\s*:\s*([^\r\n]+)') {
    $org = $Matches[1].Trim()
  }
  $attachNames = @()
  foreach ($a in @($AttachmentNames)) { if ($a) { $attachNames += [string]$a } }
  if (@($attachNames).Count -eq 0) {
    foreach ($line in ($Body -split "`r?`n")) {
      if ($line -match '붙임\s*(?:\d+\s*[.:)]\s*)?(.+?)\s*1부' -or $line -match '\(붙임\s*\d*\)\s*(.+)$') {
        $cand = $Matches[1].Trim()
        if ($cand -and $cand -notmatch '원문 첨부') { $attachNames += $cand }
      }
    }
  }
  $purpose = ''
  foreach ($ln in @($Body -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    if ($ln -match '^[12]\.\s*' -and $ln.Length -gt 10 -and $ln -notmatch '넘김') {
      $purpose = ($ln -replace '^\d+\.\s*', ''); break
    }
  }
  if (-not $purpose) { $purpose = '관련 공문에 따라 아래와 같이 안내하니 업무에 참고하시기 바랍니다.' }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine($subject); [void]$sb.AppendLine()
  if ($docNo -and $docDate) { [void]$sb.AppendLine(('1. 넘김: {0}-{1}({2})' -f $org, $docNo, $docDate)) }
  elseif ($org) { [void]$sb.AppendLine(('1. 넘김: {0}' -f $org)) }
  else { [void]$sb.AppendLine('1. 넘김: (원문 문서번호 확인)') }
  [void]$sb.AppendLine(('2. {0}' -f $purpose))
  [void]$sb.AppendLine('  가. 개요: (원문 표·핵심만 요약)')
  [void]$sb.AppendLine('  나. 기간: (원문 일정 확인)')
  [void]$sb.AppendLine('  다. 대상: (붙임 참고)')
  [void]$sb.AppendLine('  라. 행정사항; 기한 내 회신·제출 여부를 확인하시기 바랍니다.')
  [void]$sb.AppendLine()
  $ending = Format-NoticeAttachBodyEnding -Names $attachNames
  [void]$sb.AppendLine($ending)
  return ($sb.ToString().TrimEnd() + "`r`n")
}



$script:TripPortalUrl = 'https://pen.neis.go.kr/jsp/main.jsp'
$script:TripFieldMap = @{
  ListScreen = '개인출장관리'
  PortalUrl  = 'https://pen.neis.go.kr/jsp/main.jsp'
  OpenCreateButton = '신청(새 창 열기)'
  Reason = '출장목적'
  Place  = '출장지'
  Region = '출장종류'
  Start  = '시작일자'
  End    = '종료일자'
  Period = '출장기간'
}
$script:LastTripDraft = $null

function Import-TripFieldDiscovery {
  param([string]$Path = 'F:\claude\01 개발 프로그램\pen도우미\cap\trip_discovery.json')
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $obj = $raw | ConvertFrom-Json
    if ($obj.address_bar_url) {
      $u = [string]$obj.address_bar_url
      if ($u -notmatch '^https?://') { $u = 'https://' + $u }
      $script:TripPortalUrl = $u
    }
    $script:TripFieldMap = $obj
    return $obj
  } catch { return $null }
}

function Get-TripReasonFromTitle {
  param([string]$Title)
  $t = [string]$Title
  if (-not $t) { return '출장 참석' }
  $t = $t.Trim()
  $t = $t -replace '\s*신청\s*안내\s*$', ''
  $t = $t -replace '\s*안내\s*$', ''
  $t = $t -replace '\s*개최\s*$', ''
  $t = $t -replace '\s*협조\s*$', ''
  $t = $t.Trim()
  if ($t -notmatch '참석\s*$') { $t = $t + ' 참석' }
  return $t
}

function Get-TripDraftFromNotice {
  param([string]$Title, [string]$Body)
  $reason = Get-TripReasonFromTitle -Title $Title
  $text = (($Title + "`n" + $Body) -replace '\r', '')
  $place = ''
  $dateText = ''
  $timeText = ''
  $region = '관외'
  # place
  foreach ($pat in @(
    '장소\s*[:：]\s*([^\r\n]+)',
    '일시\s*및\s*장소\s*[:：]\s*([^\r\n]+)',
    '개최\s*장소\s*[:：]\s*([^\r\n]+)',
    '위\s*치\s*[:：]\s*([^\r\n]+)'
  )) {
    $m = [regex]::Match($text, $pat)
    if ($m.Success) { $place = $m.Groups[1].Value.Trim(); break }
  }
  # datetime patterns
  $m = [regex]::Match($text, '(\d{4})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})\s*일?')
  if ($m.Success) {
    $dateText = '{0}-{1:D2}-{2:D2}' -f $m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value
  }
  $m2 = [regex]::Match($text, '(\d{1,2})\s*:\s*(\d{2})\s*(?:~|-|–|—)\s*(\d{1,2})\s*:\s*(\d{2})')
  if ($m2.Success) {
    $timeText = '{0:D2}:{1} ~ {2:D2}:{3}' -f [int]$m2.Groups[1].Value, $m2.Groups[2].Value, [int]$m2.Groups[3].Value, $m2.Groups[4].Value
  } else {
    $m3 = [regex]::Match($text, '(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분)?')
    if ($m3.Success) {
      $mm = if ($m3.Groups[2].Success -and $m3.Groups[2].Value) { [int]$m3.Groups[2].Value } else { 0 }
      $timeText = '{0:D2}:{1:D2}' -f [int]$m3.Groups[1].Value, $mm
    }
  }
  # period line like 2026. 11. 5.(수) 14:00
  if (-not $dateText -or -not $timeText) {
    $m4 = [regex]::Match($text, '(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.?(?:\([^)]*\))?\s*(\d{1,2})\s*:\s*(\d{2})')
    if ($m4.Success) {
      if (-not $dateText) {
        $dateText = '{0}-{1:D2}-{2:D2}' -f $m4.Groups[1].Value, [int]$m4.Groups[2].Value, [int]$m4.Groups[3].Value
      }
      if (-not $timeText) {
        $timeText = '{0:D2}:{1}' -f [int]$m4.Groups[4].Value, $m4.Groups[5].Value
      }
    }
  }
  $probe = ($place + ' ' + $text)
  if ($probe -match '부산') { $region = '관내' } else { $region = '관외' }
  $copy = @(
    ('출장사유: {0}' -f $reason),
    ('구분: {0}' -f $region),
    ('날짜: {0}' -f $(if ($dateText) { $dateText } else { '(원문 확인)' })),
    ('시간: {0}' -f $(if ($timeText) { $timeText } else { '(원문 확인)' })),
    ('장소: {0}' -f $(if ($place) { $place } else { '(원문 확인)' }))
  ) -join "`r`n"
  return [pscustomobject]@{
    Reason = $reason
    Region = $region
    Date = $dateText
    Time = $timeText
    Place = $place
    CopyText = $copy
    PortalUrl = $(if ($script:TripPortalUrl) { [string]$script:TripPortalUrl } else { '' })
  }
}

function Show-TripReviewDialog {
  param($Draft)
  $f = New-Object System.Windows.Forms.Form
  $f.Text = '출장신청 검토'
  $f.Size = New-Object System.Drawing.Size(520, 420)
  $f.StartPosition = 'CenterParent'
  $f.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
  $f.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7')

  function Add-L([string]$Text, [int]$Y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point(16, $Y); $l.AutoSize = $true
    $f.Controls.Add($l) | Out-Null
  }
  function Add-T([string]$Val, [int]$Y, [int]$W=460) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point(16, $Y); $t.Width = $W; $t.Text = $Val
    $f.Controls.Add($t) | Out-Null
    return $t
  }
  Add-L '출장사유' 12
  $tReason = Add-T ([string]$Draft.Reason) 32
  Add-L '구분 (관내/관외)' 64
  $tRegion = Add-T ([string]$Draft.Region) 84 160
  Add-L '날짜' 116
  $tDate = Add-T ([string]$Draft.Date) 136 200
  Add-L '시간' 168
  $tTime = Add-T ([string]$Draft.Time) 188 200
  Add-L '장소' 220
  $tPlace = Add-T ([string]$Draft.Place) 240
  Add-L '포털 URL (발견 시)' 272
  $tUrl = Add-T ([string]$Draft.PortalUrl) 292

  $ok = $false
  $btnCopy = New-Object System.Windows.Forms.Button
  $btnCopy.Text = '복사만'; $btnCopy.Location = New-Object System.Drawing.Point(16, 330); $btnCopy.Width = 100; $btnCopy.Height = 32
  $btnCopy.FlatStyle='Flat'; $btnCopy.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#E8E8ED')
  $btnOpen = New-Object System.Windows.Forms.Button
  $btnOpen.Text = '포털열기(입력없음)'; $btnOpen.Location = New-Object System.Drawing.Point(130, 330); $btnOpen.Width = 150; $btnOpen.Height = 32
  $btnOpen.FlatStyle='Flat'; $btnOpen.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#0071E3'); $btnOpen.ForeColor=[System.Drawing.Color]::White
  $btnFill = New-Object System.Windows.Forms.Button
  $btnFill.Text = '필드입력(신청금지)'; $btnFill.Location = New-Object System.Drawing.Point(290, 330); $btnFill.Width = 150; $btnFill.Height = 32
  $btnFill.FlatStyle='Flat'; $btnFill.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#0071E3'); $btnFill.ForeColor=[System.Drawing.Color]::White
  $btnCancel = New-Object System.Windows.Forms.Button
  $btnCancel.Text = '닫기'; $btnCancel.Location = New-Object System.Drawing.Point(450, 330); $btnCancel.Width = 50; $btnCancel.Height = 32

  $result = [pscustomobject]@{ Confirmed=$false; Action='close'; Draft=$null }
  $btnCopy.add_Click({
    $d = [pscustomobject]@{ Reason=$tReason.Text; Region=$tRegion.Text; Date=$tDate.Text; Time=$tTime.Text; Place=$tPlace.Text; PortalUrl=$tUrl.Text }
    $d | Out-Null
    $txt = @(
      ('출장사유: {0}' -f $tReason.Text),
      ('구분: {0}' -f $tRegion.Text),
      ('날짜: {0}' -f $tDate.Text),
      ('시간: {0}' -f $tTime.Text),
      ('장소: {0}' -f $tPlace.Text)
    ) -join "`r`n"
    try { [System.Windows.Forms.Clipboard]::SetText($txt) } catch { }
    $result.Action = 'copy'; $result.Confirmed = $true
    $result.Draft = [pscustomobject]@{ Reason=$tReason.Text; Region=$tRegion.Text; Date=$tDate.Text; Time=$tTime.Text; Place=$tPlace.Text; PortalUrl=$tUrl.Text; CopyText=$txt }
    $f.Close()
  })
  $btnOpen.add_Click({
    $result.Action = 'open'
    $result.Confirmed = $true
    $result.Draft = [pscustomobject]@{ Reason=$tReason.Text; Region=$tRegion.Text; Date=$tDate.Text; Time=$tTime.Text; Place=$tPlace.Text; PortalUrl=$tUrl.Text }
    $f.Close()
  })
  $btnFill.add_Click({
    $result.Action = 'fill'
    $result.Confirmed = $true
    $result.Draft = [pscustomobject]@{ Reason=$tReason.Text; Region=$tRegion.Text; Date=$tDate.Text; Time=$tTime.Text; Place=$tPlace.Text; PortalUrl=$tUrl.Text }
    $f.Close()
  })
  $btnCancel.add_Click({ $f.Close() })
  foreach ($b in @($btnCopy,$btnOpen,$btnFill,$btnCancel)) { $f.Controls.Add($b) }
  [void]$f.ShowDialog()
  return $result
}


function Invoke-TripFormFill {
  param($Draft, [switch]$DryRun)
  # Fill NEIS 출장신청 fields via UIA. NEVER invoke 신청/상신/저장/결재올림/발송.
  Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  $copy = @(
    ('출장사유: {0}' -f $Draft.Reason),
    ('구분: {0}' -f $Draft.Region),
    ('날짜: {0}' -f $Draft.Date),
    ('시간: {0}' -f $Draft.Time),
    ('장소: {0}' -f $Draft.Place)
  ) -join "`r`n"
  try { [System.Windows.Forms.Clipboard]::SetText($copy) } catch { }

  $forbid = @('신청','상신','저장','결재올림','발송','변경신청')
  $filled = New-Object System.Collections.ArrayList
  $found = New-Object System.Collections.ArrayList
  $winInfo = ''
  $url = [string]$script:TripPortalUrl

  function Test-ForbiddenName([string]$Name) {
    if (-not $Name) { return $false }
    foreach ($f in $forbid) {
      if ($Name -eq $f) { return $true }
      if ($Name -like ($f + '*') -and $Name -notmatch '새 창 열기|조회|목록') {
        # allow list button label containing 신청(새 창 열기) only as detection, never invoke
        if ($Name -match '새 창') { return $true }
        if ($Name -eq $f -or $Name.StartsWith($f)) { return $true }
      }
    }
    if ($Name -match '^(신청|상신|저장|결재올림|발송)$') { return $true }
    if ($Name -match '신청\(새 창' -or $Name -match '변경신청' -or $Name -match '상신' -or $Name -eq '저장') { return $true }
    return $false
  }

  function Set-UiaValue($Element, [string]$Value) {
    if ($null -eq $Element -or $null -eq $Value) { return $false }
    try {
      $vp = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      if ($vp -and -not $vp.Current.IsReadOnly) { $vp.SetValue($Value); return $true }
    } catch { }
    return $false
  }

  function Select-UiaCombo($Element, [string]$Want) {
    if ($null -eq $Element -or -not $Want) { return $false }
    # try value first
    if (Set-UiaValue $Element $Want) { return $true }
    $mapped = $Want
    if ($Want -eq '관내') { $mapped = '국내출장(관내)' }
    elseif ($Want -eq '관외') { $mapped = '국내출장(관외)' }
    if ($mapped -ne $Want -and (Set-UiaValue $Element $mapped)) { return $true }
    try {
      $items = $Element.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
      foreach ($it in $items) {
        $nm = ''
        try { $nm = $it.Current.Name } catch { }
        if (-not $nm) { continue }
        if ($nm -eq $Want -or $nm -eq $mapped -or $nm -like ('*' + $Want + '*') -or ($Want -eq '관내' -and $nm -match '관내') -or ($Want -eq '관외' -and $nm -match '관외')) {
          try {
            $sel = $it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $sel.Select(); return $true
          } catch { }
        }
      }
    } catch { }
    return $false
  }

  function Get-MatchScore([string]$Name, [string[]]$Patterns) {
    if (-not $Name) { return 0 }
    $best = 0
    foreach ($p in $Patterns) {
      if ($Name -eq $p) { return 100 }
      if ($Name -like ('*' + $p + '*')) { if (80 -gt $best) { $best = 80 } }
    }
    return $best
  }

  # Enum chrome-like windows
  if (-not ('TripFillEnum' -as [type])) {
    Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TripFillEnum {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  public static List<long> Hwnds = new List<long>();
  public static bool Cb(IntPtr h, IntPtr lp) {
    if (!IsWindowVisible(h)) return true;
    var cls = new StringBuilder(256); GetClassName(h, cls, 256);
    var title = new StringBuilder(512); GetWindowText(h, title, 512);
    string c = cls.ToString(); string t = title.ToString();
    if (c.IndexOf("Chrome_WidgetWin_1") >= 0 || t.IndexOf("나이스") >= 0 || t.IndexOf("출장") >= 0)
      Hwnds.Add(h.ToInt64());
    return true;
  }
}
"@
  }
  [TripFillEnum]::Hwnds = New-Object 'System.Collections.Generic.List[long]'
  $del = [TripFillEnum+EnumProc]{ param([IntPtr]$h,[IntPtr]$lp) return [TripFillEnum]::Cb($h,$lp) }
  [TripFillEnum]::EnumWindows($del, [IntPtr]::Zero)

  $targets = @{
    Reason = @('출장목적','출장사유','목적','사유')
    Place  = @('출장지','장소')
    Region = @('출장종류')
    StartDate = @('시작일자','시작일','시작일시','출장시작일')
    EndDate = @('종료일자','종료일','종료일시','출장종료일')
    StartTime = @('시작시간','시작시각','시작시')
    EndTime = @('종료시간','종료시각','종료시')
    Transport = @('교통수단','교통')
    Expense = @('여비')
  }

  # parse time into start/end if "HH:MM ~ HH:MM"
  $startTime = ''
  $endTime = ''
  $timeRaw = [string]$Draft.Time
  if ($timeRaw -match '(\d{1,2}:\d{2})\s*[~～\-–—]\s*(\d{1,2}:\d{2})') {
    $startTime = $Matches[1]; $endTime = $Matches[2]
  } elseif ($timeRaw -match '(\d{1,2}:\d{2})') {
    $startTime = $Matches[1]
  }
  $regionVal = [string]$Draft.Region
  if ($regionVal -match '관내') { $regionVal = '관내' }
  elseif ($regionVal -match '관외') { $regionVal = '관외' }

  $values = @{
    Reason = [string]$Draft.Reason
    Place = [string]$Draft.Place
    Region = $regionVal
    StartDate = [string]$Draft.Date
    EndDate = [string]$Draft.Date
    StartTime = $startTime
    EndTime = $endTime
    Transport = ''
    Expense = ''
  }

  $bestRoot = $null
  $bestScore = -1
  foreach ($id in [TripFillEnum]::Hwnds) {
    try {
      $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$id)
    } catch { continue }
    $score = 0
    $title = ''
    try { $title = $root.Current.Name } catch { }
    if ($title -match '출장') { $score += 5 }
    if ($title -match '나이스') { $score += 2 }
    # look for create-form-like fields (목적/출장지 edits), not only list filters
    foreach ($typeName in @('Edit','ComboBox')) {
      $ct = [System.Windows.Automation.ControlType]::$typeName
      $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
      foreach ($e in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
        $nm = ''
        try { $nm = $e.Current.Name } catch { }
        if ($nm -match '출장목적|출장사유|출장지') { $score += 20 }
        if ($nm -match '여비|교통수단') { $score += 15 }
        if ($nm -eq '출장종류' -or $nm -like '출장종류*') { $score += 3 }
      }
    }
    if ($score -gt $bestScore) { $bestScore = $score; $bestRoot = $root; $winInfo = ("h={0} title=[{1}] score={2}" -f $id, $title, $score) }
  }

  if ($null -eq $bestRoot -or $bestScore -lt 15) {
    $msg = '출장신청 입력 폼 창을 못 찾음(목록만 보이거나 새 창 미오픈). 클립보드에 값 복사됨. ' + $winInfo
    try { Import-TripFieldDiscovery | Out-Null } catch { }
    return [pscustomobject]@{ Ok=$false; DryRun=[bool]$DryRun; Message=$msg; CopyText=$copy; Url=$url; Filled=@($filled); Found=@($found); Window=$winInfo }
  }

  # collect candidate controls
  $controls = New-Object System.Collections.ArrayList
  foreach ($typeName in @('Edit','ComboBox','Document')) {
    $ct = [System.Windows.Automation.ControlType]::$typeName
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
    foreach ($e in $bestRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
      $nm = ''; $auto = ''
      try { $nm = $e.Current.Name; $auto = $e.Current.AutomationId } catch { continue }
      if (Test-ForbiddenName $nm) { continue }
      [void]$controls.Add([pscustomobject]@{ El=$e; Name=$nm; Auto=$auto; Type=$typeName })
      [void]$found.Add(("{0}:{1}" -f $typeName, $nm))
    }
  }

  if ($DryRun) {
    return [pscustomobject]@{ Ok=$true; DryRun=$true; Message=('드라이런: 폼 후보 점수={0} {1}' -f $bestScore, $winInfo); CopyText=$copy; Url=$url; Filled=@(); Found=@($found); Window=$winInfo }
  }

  foreach ($key in @('Reason','Place','Region','StartDate','EndDate','StartTime','EndTime','Transport','Expense')) {
    $val = [string]$values[$key]
    if (-not $val) { continue }
    $patterns = [string[]]$targets[$key]
    $best = $null; $bs = 0
    foreach ($c in $controls) {
      $s = Get-MatchScore $c.Name $patterns
      # skip list filter 시작/종료 when create form also has richer names - still allow if best
      if ($s -gt $bs) { $bs = $s; $best = $c }
    }
    if ($null -eq $best -or $bs -lt 80) { continue }
    $okSet = $false
    if ($key -eq 'Region' -or $best.Type -eq 'ComboBox') {
      $okSet = Select-UiaCombo $best.El $val
    } else {
      $okSet = Set-UiaValue $best.El $val
    }
    if ($okSet) { [void]$filled.Add(("{0}->{1} [{2}]" -f $key, $val, $best.Name)) }
    else { [void]$filled.Add(("{0} FAIL [{1}]" -f $key, $best.Name)) }
  }

  # explicitly ensure we never invoke forbidden buttons (scan only)
  $btnCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $skipped = New-Object System.Collections.ArrayList
  foreach ($b in $bestRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    $bn = ''
    try { $bn = $b.Current.Name } catch { }
    if (Test-ForbiddenName $bn) { [void]$skipped.Add($bn) }
  }

  $msg = ('입력 {0}건 / 금지버튼 미클릭 {1}' -f @($filled).Count, ($skipped -join ','))
  return [pscustomobject]@{ Ok=(@($filled).Count -gt 0); DryRun=$false; Message=$msg; CopyText=$copy; Url=$url; Filled=@($filled); Found=@($found); Window=$winInfo; SkippedButtons=@($skipped) }
}

function Mask-PersonalInfo {
  param([string]$Text)
  $pairList = New-Object System.Collections.ArrayList
  $counts = @{ name = 0; phone = 0; email = 0; rrn = 0; account = 0; addr = 0 }
  $labelMap = @{ name = '이름'; phone = '전화'; email = '이메일'; rrn = '주민번호'; account = '계좌'; addr = '주소' }
  $work = [string]$Text

  function Get-MaskPlaceholder {
    param([string]$Value, [string]$Kind)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    foreach ($p in $pairList) {
      if ([string]$p.Value -eq $Value) { return [string]$p.Placeholder }
    }
    $counts[$Kind] = [int]$counts[$Kind] + 1
    $ph = '[' + $labelMap[$Kind] + [string]$counts[$Kind] + ']'
    [void]$pairList.Add([pscustomobject]@{ Placeholder = $ph; Value = $Value; Kind = $Kind })
    return $ph
  }

  function Protect-Orgs {
    param([string]$S)
    $orgTokens = New-Object System.Collections.ArrayList
    $rx = [regex]'([가-힣]{2,20}(?:초등학교|중학교|고등학교|교육지원청|교육청|대학교|대학))'
    $ms = $rx.Matches($S)
    for ($i = $ms.Count - 1; $i -ge 0; $i--) {
      $m = $ms[$i]
      $v = $m.Value
      $existing = $null
      foreach ($o in $orgTokens) { if ($o.Value -eq $v) { $existing = $o; break } }
      if ($null -eq $existing) {
        $token = '<<ORG' + ($orgTokens.Count + 1) + '>>'
        [void]$orgTokens.Add([pscustomobject]@{ Token = $token; Value = $v })
      } else {
        $token = [string]$existing.Token
      }
      $S = $S.Remove($m.Index, $m.Length).Insert($m.Index, $token)
    }
    foreach ($fixed in @('부산광역시교육청','교육부','한국기술교육대학교','직업계고','특성화고')) {
      if ($S.Contains($fixed)) {
        $dup = $false
        foreach ($o in $orgTokens) { if ($o.Value -eq $fixed) { $dup = $true; break } }
        if (-not $dup) {
          $token = '<<ORG' + ($orgTokens.Count + 1) + '>>'
          [void]$orgTokens.Add([pscustomobject]@{ Token = $token; Value = $fixed })
          $S = $S.Replace($fixed, $token)
        }
      }
    }
    return @{ Text = $S; Orgs = $orgTokens }
  }

  function Replace-ByRegex {
    param([string]$S, [string]$Pattern, [scriptblock]$Replacer)
    $rx = [regex]$Pattern
    $ms = $rx.Matches($S)
    for ($i = $ms.Count - 1; $i -ge 0; $i--) {
      $m = $ms[$i]
      $rep = [string](& $Replacer $m)
      $S = $S.Remove($m.Index, $m.Length).Insert($m.Index, $rep)
    }
    return $S
  }

  $prot = Protect-Orgs -S $work
  $work = [string]$prot.Text
  $orgTokens = $prot.Orgs

  $work = Replace-ByRegex -S $work -Pattern '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}' -Replacer {
    param($m) return (Get-MaskPlaceholder -Value $m.Value -Kind 'email')
  }
  $work = Replace-ByRegex -S $work -Pattern '(?<!\d)\d{6}[-\s]?\d{7}(?!\d)' -Replacer {
    param($m) return (Get-MaskPlaceholder -Value $m.Value -Kind 'rrn')
  }
  $work = Replace-ByRegex -S $work -Pattern '(?<!\d)(0\d{1,2}[-.\s]?\d{3,4}[-.\s]?\d{4})(?!\d)' -Replacer {
    param($m) return (Get-MaskPlaceholder -Value $m.Value -Kind 'phone')
  }
  $work = Replace-ByRegex -S $work -Pattern '(?<!\d)(\d{2,6}[- ]\d{2,6}[- ]\d{2,6}(?:[- ]\d{2,6})?)(?!\d)' -Replacer {
    param($m)
    $d = ($m.Value -replace '\D','')
    if ($d.Length -ge 10) { return (Get-MaskPlaceholder -Value $m.Value -Kind 'account') }
    return $m.Value
  }
  $work = Replace-ByRegex -S $work -Pattern '((?:담당자|성명|작성자|기안자|처리자)\s*[:：]?\s*)([가-힣]{2,4})' -Replacer {
    param($m)
    $nm = $m.Groups[2].Value
    if ($nm -match '학교|교육|부서|과장|장학|교사') { return $m.Value }
    return ($m.Groups[1].Value + (Get-MaskPlaceholder -Value $nm -Kind 'name'))
  }
  $work = Replace-ByRegex -S $work -Pattern '((?:주소|소재지)\s*[:：]\s*)([^\r\n]+)' -Replacer {
    param($m)
    return ($m.Groups[1].Value + (Get-MaskPlaceholder -Value $m.Groups[2].Value.Trim() -Kind 'addr'))
  }

  foreach ($o in $orgTokens) {
    $work = $work.Replace([string]$o.Token, [string]$o.Value)
  }

  $pairArr = @()
  foreach ($p in $pairList) { $pairArr += $p }
  return [pscustomobject]@{ Masked = [string]$work; Pairs = $pairArr }
}

function Unmask-PersonalInfo {
  param([string]$Text, $Pairs)
  $r = $Text
  foreach ($p in @($Pairs | Sort-Object { $_.Placeholder.Length } -Descending)) {
    $r = $r.Replace([string]$p.Placeholder, [string]$p.Value)
  }
  return $r
}

function Save-MaskMapFile {
  param($Pairs, [string]$Stamp)
  $path = Join-Path $script:MaskMapDir ($Stamp + '.json')
  Write-JsonFile -Path $path -Object @{ Stamp = $Stamp; Created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Pairs = @($Pairs) }
  $script:LastMaskMapPath = $path
  return $path
}
