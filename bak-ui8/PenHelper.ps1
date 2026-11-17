#Requires -Version 5.1
<#
.SYNOPSIS
  PEN 업무 도우미 2차 — 개인용 (교육청 PC)
.NOTES
  - 메신저 설정/파일 수정 금지
  - 비밀번호 저장 금지
  - 네트워크 전송 없음 (Chrome 열기·그록 붙여넣기·구글캘린더 템플릿 제외)
  - 데이터: %LOCALAPPDATA%\PenHelper\ 및 F:\claude\01 개발 프로그램\pen도우미\outbox\
  - 결재올림/발송/상신 절대 클릭 금지
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ---------- 경로 / 저장 ----------
$script:AppName = 'PEN 업무 도우미'
$script:DataDir = Join-Path $env:LOCALAPPDATA 'PenHelper'
$script:TodosPath = Join-Path $script:DataDir 'todos.json'
$script:SeenPath = Join-Path $script:DataDir 'seen_windows.json'
$script:DraftDir = Join-Path $script:DataDir 'drafts'
$script:SchedulesPath = Join-Path $script:DataDir 'schedules.json'

foreach ($d in @($script:DataDir, $script:DraftDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# ---------- URL (로그인은 사용자 직접) ----------
$script:Urls = [ordered]@{
    '결재대기' = 'https://klef.pen.go.kr/portal/link.do?link=sanctnWait'
    '문서진행' = 'https://klef.pen.go.kr/portal/link.do?link=sanctnView'
    '공람'     = 'https://klef.pen.go.kr/portal/link.do?link=dsplayWait'
    '발송대기' = 'https://klef.pen.go.kr/portal/link.do?link=sendWait'
    '공문접수' = 'https://klef.pen.go.kr/portal/link.do?link=recvWait'
    '업무포털' = 'https://pen.eduptl.kr/bpm_man_mn00_001.do'
}

$script:Keywords = @('결재', '공람', '기안', '발송', '협조')
$script:KeywordToButton = @{
    '결재' = '결재대기'
    '공람' = '공람'
    '기안' = '업무포털'
    '발송' = '발송대기'
    '협조' = '업무포털'
}

# ---------- JSON ----------
function Read-JsonFile {
    param([string]$Path, $Default)
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $Default
    }
}

function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 8
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $json, $utf8bom)
}

# 안내공문 모듈 (JSON 헬퍼 정의 후 로드)
$script:NoticeHelper = Join-Path $PSScriptRoot 'PenNotice.ps1'
$script:NoticeUi = Join-Path $PSScriptRoot 'PenNoticeUi.ps1'
if (Test-Path -LiteralPath $script:NoticeHelper) {
    try { . $script:NoticeHelper } catch { Write-Host ('PenNotice load: ' + $_.Exception.Message) }
}
if (Test-Path -LiteralPath $script:NoticeUi) {
    try { . $script:NoticeUi } catch { Write-Host ('PenNoticeUi load: ' + $_.Exception.Message) }
}
if (-not (Get-Variable -Name NoticeFitChrome -Scope Script -ErrorAction SilentlyContinue)) { $script:NoticeFitChrome = $null }
if (-not (Get-Variable -Name TripFitChrome -Scope Script -ErrorAction SilentlyContinue)) { $script:TripFitChrome = $null }
$script:GoogleCalHelper = Join-Path $PSScriptRoot 'PenGoogleCal.ps1'
if (Test-Path -LiteralPath $script:GoogleCalHelper) {
    try { . $script:GoogleCalHelper } catch { Write-Host ('PenGoogleCal load: ' + $_.Exception.Message) }
}

$script:ExtrasHelper = Join-Path $PSScriptRoot 'PenExtras.ps1'
if (Test-Path -LiteralPath $script:ExtrasHelper) {
    try { . $script:ExtrasHelper } catch { Write-Host ('PenExtras load: ' + $_.Exception.Message) }
}


function Get-Todos {
    $data = Read-JsonFile -Path $script:TodosPath -Default @()
    if ($null -eq $data) { return @() }
    if ($data -isnot [System.Array]) { return @($data) }
    return @($data)
}

function Save-Todos {
    param($Todos)
    Write-JsonFile -Path $script:TodosPath -Object @($Todos)
}

function Get-SeenMap {
    $data = Read-JsonFile -Path $script:SeenPath -Default $null
    $map = @{}
    if ($null -eq $data) { return $map }
    if ($data -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $data.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    return $map
}

function Save-SeenMap {
    param($Map)
    Write-JsonFile -Path $script:SeenPath -Object $Map
}

# ---------- Chrome ----------
function Open-InChrome {
    param([string]$Url)
    $candidates = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $chrome = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $chrome = $c; break }
    }
    try {
        if ($chrome) {
            Start-Process -FilePath $chrome -ArgumentList $Url | Out-Null
        } else {
            Start-Process $Url | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            ("브라우저를 열 수 없습니다.`n{0}" -f $_.Exception.Message),
            $script:AppName, 'OK', 'Warning'
        ) | Out-Null
    }
}

# ---------- 날짜 추출 ----------
function Get-DueDateFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $now = Get-Date
    $year = $now.Year

    if ($Text -match '오늘') { return $now.Date.ToString('yyyy-MM-dd') }
    if ($Text -match '내일') { return $now.Date.AddDays(1).ToString('yyyy-MM-dd') }
    if ($Text -match '모레') { return $now.Date.AddDays(2).ToString('yyyy-MM-dd') }

    if ($Text -match '(\d{1,2})\s*월\s*(\d{1,2})\s*일') {
        $m = [int]$Matches[1]; $d = [int]$Matches[2]
        try {
            $dt = Get-Date -Year $year -Month $m -Day $d
            if ($dt.Date -lt $now.Date.AddMonths(-1)) { $dt = $dt.AddYears(1) }
            return $dt.ToString('yyyy-MM-dd')
        } catch { }
    }

    if ($Text -match '(?<!\d)(\d{1,2})[./\-](\d{1,2})(?:[./\-](\d{2,4}))?(?!\d)') {
        $m = [int]$Matches[1]; $d = [int]$Matches[2]
        $y = $year
        if ($Matches[3]) {
            $yPart = [int]$Matches[3]
            if ($yPart -lt 100) { $y = 2000 + $yPart } else { $y = $yPart }
        }
        try {
            $dt = Get-Date -Year $y -Month $m -Day $d
            if (-not $Matches[3] -and $dt.Date -lt $now.Date.AddMonths(-1)) {
                $dt = $dt.AddYears(1)
            }
            return $dt.ToString('yyyy-MM-dd')
        } catch { }
    }
    return $null
}

function Get-CategoryFromText {
    param([string]$Text)
    foreach ($kw in $script:Keywords) {
        if ($Text -like ("*{0}*" -f $kw)) { return $kw }
    }
    return $null
}

# ---------- UI Automation ----------
function Get-UcwareProcessIds {
    try {
        return @(Get-Process -Name 'ucware_m' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)
    } catch {
        return @()
    }
}

function Get-ElementTextSafe {
    param($Element)
    if ($null -eq $Element) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        $name = $Element.Current.Name
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$parts.Add($name) }
    } catch { }
    try {
        $vp = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($null -ne $vp -and -not [string]::IsNullOrWhiteSpace($vp.Current.Value)) {
            [void]$parts.Add([string]$vp.Current.Value)
        }
    } catch { }
    try {
        $tp = $Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if ($null -ne $tp) {
            $doc = $tp.DocumentRange.GetText(-1)
            if (-not [string]::IsNullOrWhiteSpace($doc)) { [void]$parts.Add($doc) }
        }
    } catch { }
    return ($parts -join "`n")
}

function Get-DescendantTexts {
    param($Root, [int]$MaxDepth = 4, [int]$MaxNodes = 80)

    $bag = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Root) { return '' }

    # BFS (중첩 함수 회피 — PS 5.1 안정)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue(@{ El = $Root; Depth = 0 })
    $visited = 0

    while ($queue.Count -gt 0 -and $visited -lt $MaxNodes) {
        $item = $queue.Dequeue()
        $el = $item.El
        $depth = [int]$item.Depth
        if ($null -eq $el) { continue }
        $visited++

        try {
            $t = Get-ElementTextSafe -Element $el
            if (-not [string]::IsNullOrWhiteSpace($t) -and $t.Length -lt 4000) {
                [void]$bag.Add($t.Trim())
            }
        } catch { }

        if ($depth -ge $MaxDepth) { continue }
        try {
            $children = $el.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition
            )
            foreach ($c in $children) {
                if ($visited + $queue.Count -ge $MaxNodes) { break }
                $queue.Enqueue(@{ El = $c; Depth = ($depth + 1) })
            }
        } catch { }
    }

    $uniq = @($bag | Select-Object -Unique | Select-Object -First 30)
    return ($uniq -join "`n---`n")
}

function Get-UcwareTopWindows {
    $pids = @(Get-UcwareProcessIds)
    if (@($pids).Count -eq 0) { return @() }

    $results = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $wins = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        foreach ($w in $wins) {
            try {
                $pid = $w.Current.ProcessId
                if ($pids -notcontains $pid) { continue }
                $title = [string]$w.Current.Name
                if ([string]::IsNullOrWhiteSpace($title)) { continue }
                $rect = $w.Current.BoundingRectangle
                if ($rect.Width -lt 80 -or $rect.Height -lt 40) { continue }

                $body = ''
                try { $body = Get-DescendantTexts -Root $w } catch { $body = '' }

                $hwnd = $w.Current.NativeWindowHandle
                $key = '{0}|{1}' -f $pid, $hwnd
                $results += [pscustomobject]@{
                    Key   = $key
                    Title = $title
                    Body  = $body
                    Pid   = $pid
                }
            } catch { }
        }
    } catch { }
    return @($results)
}

# ---------- 초안 ----------
function New-NoticeDraft {
    param([string]$Title, [string]$Body, [string]$Due)

    $subject = if ($Title) { $Title } else { '안내 공문 초안' }
    $dueLine = if ($Due) { $Due } else { '(일정 미확인 — 직접 입력)' }
    $content = if ($Body) { $Body } else { '(내용 없음)' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('[제목]')
    [void]$sb.AppendLine($subject)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('[내용]')
    [void]$sb.AppendLine($content)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('[일정]')
    [void]$sb.AppendLine($dueLine)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('[대상]')
    [void]$sb.AppendLine('(대상 미확인 — 직접 입력)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('※ 1차 버전: 텍스트 초안입니다. HWPX는 2차에서 지원.')
    [void]$sb.AppendLine(('※ 작성시각: {0} KST' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))

    $text = $sb.ToString()
    $safeBase = ($subject -replace '[\\/:*?"<>|]', '_')
    if ($safeBase.Length -gt 40) { $safeBase = $safeBase.Substring(0, 40) }
    $fname = '{0}_{1}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $safeBase
    $path = Join-Path $script:DraftDir $fname
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($path, $text, $utf8bom)
    try { [System.Windows.Forms.Clipboard]::SetText($text) } catch { }
    return $path
}


# ---------- Apple-like theme helpers ----------
$script:SettingsPath = Join-Path $script:DataDir 'settings.json'
$script:ThemeName = 'black'
$script:ThemeDefs = [ordered]@{
  # Apple HIG semantic mapping — see research/apple-hig.md
  black = @{
    Label='블랙'; Bg='#000000'; Card='#1C1C1E'; Tile='#2C2C2E'; Sidebar='#1C1C1E'
    Accent='#0A84FF'; AccentSoft='#64D2FF'; Text='#FFFFFF'; Muted='#98989D'
    Border='#38383A'; Danger='#FF453A'; Success='#30D158'
    Hover='#3A3A3C'; Pressed='#48484A'; AccentHover='#409CFF'; AccentPressed='#0066CC'
    StatusBg='#1C1C1E'; HeaderBg='#1C1C1E'; ChipBg='#2C2C2E'
  }
  sky = @{
    Label='하늘'; Bg='#EAF4FF'; Card='#FFFFFF'; Tile='#D6EBFF'; Sidebar='#D9EEFF'
    Accent='#007AFF'; AccentSoft='#5AC8FA'; Text='#000000'; Muted='#5A6A7A'
    Border='#B8D4F0'; Danger='#FF3B30'; Success='#34C759'
    Hover='#C5E2FF'; Pressed='#A8D4FF'; AccentHover='#0066D6'; AccentPressed='#0055B3'
    StatusBg='#D9EEFF'; HeaderBg='#FFFFFF'; ChipBg='#EAF4FF'
  }
  pink = @{
    Label='핑크'; Bg='#FFF0F5'; Card='#FFFFFF'; Tile='#FFE4EC'; Sidebar='#FFE8F0'
    Accent='#FF2D55'; AccentSoft='#FF6B9A'; Text='#000000'; Muted='#8E6A75'
    Border='#FFD0DC'; Danger='#FF3B30'; Success='#34C759'
    Hover='#FFD6E3'; Pressed='#FFC0D4'; AccentHover='#E0264C'; AccentPressed='#C41E3A'
    StatusBg='#FFE8F0'; HeaderBg='#FFFFFF'; ChipBg='#FFF0F5'
  }
  white = @{
    Label='화이트'; Bg='#F2F2F7'; Card='#FFFFFF'; Tile='#E5E5EA'; Sidebar='#F2F2F7'
    Accent='#007AFF'; AccentSoft='#5AC8FA'; Text='#000000'; Muted='#8E8E93'
    Border='#C6C6C8'; Danger='#FF3B30'; Success='#34C759'
    Hover='#D8D8DC'; Pressed='#C7C7CC'; AccentHover='#0066D6'; AccentPressed='#0055B3'
    StatusBg='#F2F2F7'; HeaderBg='#FFFFFF'; ChipBg='#E5E5EA'
  }
}

$script:UiBg       = [System.Drawing.Color]::Black
$script:UiCard     = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E')
$script:UiTile     = [System.Drawing.ColorTranslator]::FromHtml('#2C2C2E')
$script:UiSidebar  = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E')
$script:UiAccent   = [System.Drawing.ColorTranslator]::FromHtml('#0A84FF')
$script:UiAccentHex= '#0A84FF'
$script:UiAccentSoft = [System.Drawing.ColorTranslator]::FromHtml('#64D2FF')
$script:UiText     = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7')
$script:UiMuted    = [System.Drawing.ColorTranslator]::FromHtml('#98989D')
$script:UiBorder   = [System.Drawing.ColorTranslator]::FromHtml('#38383A')
$script:UiBtnSoft  = [System.Drawing.ColorTranslator]::FromHtml('#2C2C2E')
$script:UiDanger   = [System.Drawing.ColorTranslator]::FromHtml('#FF453A')
$script:UiSuccess  = [System.Drawing.ColorTranslator]::FromHtml('#32D74B')
$script:UiHover    = [System.Drawing.ColorTranslator]::FromHtml('#3A3A3C')
$script:UiPressed  = [System.Drawing.ColorTranslator]::FromHtml('#48484A')
$script:UiAccentHover = [System.Drawing.ColorTranslator]::FromHtml('#409CFF')
$script:UiAccentPressed = [System.Drawing.ColorTranslator]::FromHtml('#0066CC')
$script:UiStatusBg = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E')
$script:UiHeaderBg = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E')
$script:UiChipBg   = [System.Drawing.ColorTranslator]::FromHtml('#2C2C2E')
$script:UiFontUi   = New-Object System.Drawing.Font('맑은 고딕', 12)
$script:UiFontBtn  = New-Object System.Drawing.Font('맑은 고딕', 11, [System.Drawing.FontStyle]::Bold)
$script:UiFontTitle= New-Object System.Drawing.Font('맑은 고딕', 15, [System.Drawing.FontStyle]::Bold)
$script:UiFontSection = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
$script:UiFontCaption = New-Object System.Drawing.Font('맑은 고딕', 9)

function Get-PenSettings {
  $d = Read-JsonFile -Path $script:SettingsPath -Default $null
  if ($null -eq $d) {
    return [pscustomobject]@{ Theme = 'black' }
  }
  $th = 'black'
  try { if ($d.Theme) { $th = [string]$d.Theme } } catch { }
  if (-not $script:ThemeDefs.Contains($th)) { $th = 'black' }
  return [pscustomobject]@{ Theme = $th }
}

function Save-PenSettings {
  param([string]$Theme)
  if (-not $Theme) { $Theme = $script:ThemeName }
  if (-not $script:ThemeDefs.Contains($Theme)) { $Theme = 'black' }
  Write-JsonFile -Path $script:SettingsPath -Object ([pscustomobject]@{ Theme = $Theme; Updated = (Get-Date -Format 'o') })
}

function Set-RoundedRegion {
  param($Control, [int]$Radius = 12)
  if ($null -eq $Control) { return }
  if ($Control.Width -lt 2 -or $Control.Height -lt 2) { return }
  try {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $w = $Control.Width
    $h = $Control.Height
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($w - $d, 0, $d, $d, 270, 90)
    $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $path.AddArc(0, $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $Control.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
  } catch { }
}

function Get-UiColorFromTag {
  param($Control)
  if ($null -eq $Control) { return $null }
  $t = $Control.Tag
  if ($t -is [string] -and $t -like 'uicolor:*') {
    $rest = $t.Substring(8)
    if ($rest -match '^([^;]+)') { return $Matches[1] }
    return $rest
  }
  if ($t -is [hashtable] -and $t.ContainsKey('UiColor')) { return [string]$t['UiColor'] }
  try {
    if ($null -ne $t.UiColor) { return [string]$t.UiColor }
  } catch { }
  return $null
}

function Resolve-ThemeColorHex {
  param([string]$Hex)
  if (-not $Hex) { return $Hex }
  $h = $Hex.ToUpperInvariant()
  # Map legacy soft / accent tokens onto active theme
  if ($h -eq '#E5E5EA' -or $h -eq '#F2F2F7' -or $h -eq '#D6EBFF' -or $h -eq '#FFE4EC' -or $h -eq '#2C2C2E') {
    return $script:ThemeDefs[$script:ThemeName].Tile
  }
  if ($h -eq '#007AFF' -or $h -eq '#0071E3' -or $h -eq '#0A84FF' -or $h -eq '#FF2D55') {
    return $script:UiAccentHex
  }
  if ($h -eq '#8E8E93') { return $script:ThemeDefs[$script:ThemeName].Muted }
  return $Hex
}

function Set-AppleButton {
  param(
    $Button,
    [switch]$Secondary,
    [string]$AccentHex = ''
  )
  if ($null -eq $Button) { return }
  $Button.FlatStyle = 'Flat'
  $Button.Font = $script:UiFontBtn
  $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
  $Button.UseVisualStyleBackColor = $false
  $tag = [string]$Button.Tag
  $outline = ($tag -like '*;outline*')
  $isTile = ($tag -like '*;tile*' -or ($Button.Width -ge 100 -and $Button.Height -ge 60))
  if (-not $AccentHex) {
    $AccentHex = Get-UiColorFromTag -Control $Button
  }
  $AccentHex = Resolve-ThemeColorHex -Hex $AccentHex
  $isAccent = $false
  if ($AccentHex -and ($AccentHex.ToUpperInvariant() -eq $script:UiAccentHex.ToUpperInvariant())) {
    $isAccent = $true
  } elseif ($AccentHex -eq '#007AFF' -or $AccentHex -eq '#0A84FF' -or $AccentHex -eq '#FF2D55') {
    $isAccent = $true
    $AccentHex = $script:UiAccentHex
  }

  if ($outline) {
    $Button.BackColor = $script:UiCard
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = $script:UiBorder
    $Button.FlatAppearance.MouseOverBackColor = $script:UiHover
    $Button.FlatAppearance.MouseDownBackColor = $script:UiPressed
  } elseif ($isAccent -and -not $isTile) {
    $Button.BackColor = $script:UiAccent
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderSize = 0
    $Button.FlatAppearance.MouseOverBackColor = $script:UiAccentHover
    $Button.FlatAppearance.MouseDownBackColor = $script:UiAccentPressed
  } elseif ($AccentHex -and -not $isAccent) {
    # soft tile / secondary
    $Button.BackColor = $script:UiTile
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 0
    $Button.FlatAppearance.MouseOverBackColor = $script:UiHover
    $Button.FlatAppearance.MouseDownBackColor = $script:UiPressed
  } elseif ($Secondary) {
    $Button.BackColor = $script:UiBtnSoft
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 0
    $Button.FlatAppearance.MouseOverBackColor = $script:UiHover
    $Button.FlatAppearance.MouseDownBackColor = $script:UiPressed
  } else {
    $Button.BackColor = $script:UiAccent
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderSize = 0
    $Button.FlatAppearance.MouseOverBackColor = $script:UiAccentHover
    $Button.FlatAppearance.MouseDownBackColor = $script:UiAccentPressed
  }
  if ($isTile) {
    # tiles stay soft even if tagged accent (except pure accent action tiles)
    if (-not $isAccent) {
      $Button.BackColor = $script:UiTile
      $Button.ForeColor = $script:UiText
      $Button.FlatAppearance.MouseOverBackColor = $script:UiHover
      $Button.FlatAppearance.MouseDownBackColor = $script:UiPressed
    } else {
      $Button.BackColor = $script:UiAccent
      $Button.ForeColor = [System.Drawing.Color]::White
      $Button.FlatAppearance.MouseOverBackColor = $script:UiAccentHover
      $Button.FlatAppearance.MouseDownBackColor = $script:UiAccentPressed
    }
    Set-RoundedRegion -Control $Button -Radius 12
  } elseif (-not $outline) {
    Set-RoundedRegion -Control $Button -Radius 8
  } else {
    $Button.Region = $null
  }
}

function Apply-AppleTheme {
  param($Root)
  if ($null -eq $Root) { return }
  $queue = New-Object System.Collections.Generic.Queue[object]
  $queue.Enqueue($Root)
  while ($queue.Count -gt 0) {
    $c = $queue.Dequeue()
    try {
      if ($c -is [System.Windows.Forms.Form]) {
        $c.BackColor = $script:UiBg
        $c.Font = $script:UiFontUi
        $c.ForeColor = $script:UiText
      }
      elseif ($c -is [System.Windows.Forms.TabControl]) {
        $c.Font = $script:UiFontUi
        $c.BackColor = $script:UiBg
        $c.Appearance = 'Normal'
        $c.SizeMode = 'Fixed'
        $c.ItemSize = New-Object System.Drawing.Size(110, 30)
        $c.Padding = New-Object System.Drawing.Point(12, 6)
      }
      elseif ($c -is [System.Windows.Forms.TabPage]) {
        $c.BackColor = $script:UiBg
        $c.Font = $script:UiFontUi
        $c.UseVisualStyleBackColor = $false
      }
      elseif ($c -is [System.Windows.Forms.GroupBox]) {
        $c.BackColor = $script:UiCard
        $c.ForeColor = $script:UiMuted
        $c.Font = $script:UiFontUi
        $c.Padding = New-Object System.Windows.Forms.Padding(8)
      }
      elseif ($c -is [System.Windows.Forms.Panel] -or $c -is [System.Windows.Forms.FlowLayoutPanel]) {
        $tag = [string]$c.Tag
        if ($tag -eq 'bg') {
          $c.BackColor = $script:UiBg
        } elseif ($tag -eq 'card') {
          $c.BackColor = $script:UiCard
          $c.Region = $null
        } elseif ($tag -eq 'sidebar') {
          $c.BackColor = $script:UiSidebar
        } elseif ($tag -eq 'header') {
          $c.BackColor = $script:UiHeaderBg
        } elseif ($tag -eq 'statusbar') {
          $c.BackColor = $script:UiStatusBg
        } elseif ($c.Dock -eq 'Fill' -or $c.Height -gt 48 -or $c.Width -gt 200) {
          $c.BackColor = $script:UiCard
        } else {
          $c.BackColor = $script:UiBg
        }
        # HIG base 8pt; dense desktop → clamp 4–8 (no empty whitespace)
        $c.Padding = New-Object System.Windows.Forms.Padding(
          [Math]::Min(8, [Math]::Max($c.Padding.Left, 4)),
          [Math]::Min(8, [Math]::Max($c.Padding.Top, 4)),
          [Math]::Min(8, [Math]::Max($c.Padding.Right, 4)),
          [Math]::Min(8, [Math]::Max($c.Padding.Bottom, 4))
        )
      }
      elseif ($c -is [System.Windows.Forms.Button]) {
        $hex = Get-UiColorFromTag -Control $c
        if ($hex -eq '#FF3B30') { $hex = $script:ThemeDefs[$script:ThemeName].Tile }
        # theme toggle pills
        if ([string]$c.Name -like 'theme_*') {
          $key = ([string]$c.Name) -replace '^theme_',''
          $sel = ($key -eq $script:ThemeName)
          if ($sel) {
            $c.BackColor = $script:UiAccent
            $c.ForeColor = [System.Drawing.Color]::White
            $c.FlatAppearance.BorderSize = 0
            $c.FlatAppearance.MouseOverBackColor = $script:UiAccentHover
            $c.FlatAppearance.MouseDownBackColor = $script:UiAccentPressed
          } else {
            $c.BackColor = $script:UiTile
            $c.ForeColor = $script:UiText
            $c.FlatAppearance.BorderSize = 0
            $c.FlatAppearance.MouseOverBackColor = $script:UiHover
            $c.FlatAppearance.MouseDownBackColor = $script:UiPressed
          }
          Set-RoundedRegion -Control $c -Radius 10
        } elseif ($hex) {
          Set-AppleButton -Button $c -AccentHex $hex
        } else {
          $sec = ($c.Text -match '삭제|취소|◀|▶|접기|더보기')
          Set-AppleButton -Button $c -Secondary:$sec
        }
      }
      elseif ($c -is [System.Windows.Forms.Label]) {
        if ([string]$c.Tag -eq 'section') {
          $c.ForeColor = $script:UiMuted
          $c.Font = $script:UiFontSection
          $c.BackColor = [System.Drawing.Color]::Transparent
        } elseif ([string]$c.Tag -eq 'stephead') {
          $c.ForeColor = $script:UiText
          $c.Font = $script:UiFontTitle
          $c.BackColor = [System.Drawing.Color]::Transparent
        } elseif ([string]$c.Tag -eq 'statusbar') {
          $c.ForeColor = $script:UiMuted
          $c.BackColor = $script:UiStatusBg
          $c.Font = $script:UiFontCaption
        } elseif ([string]$c.Tag -eq 'safety') {
          $c.ForeColor = $script:UiDanger
          $c.BackColor = [System.Drawing.Color]::Transparent
        } elseif ([string]$c.Name -eq 'statusChips') {
          $c.ForeColor = $script:UiMuted
          $c.BackColor = [System.Drawing.Color]::Transparent
        } else {
          $c.ForeColor = $script:UiText
          $c.Font = $script:UiFontUi
          if ($c.BackColor.A -ne 0 -and $c.BackColor -ne [System.Drawing.Color]::Transparent) {
            # leave parent-driven
          } else {
            $c.BackColor = [System.Drawing.Color]::Transparent
          }
        }
      }
      elseif ($c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.RichTextBox]) {
        $c.BorderStyle = 'FixedSingle'
        $c.BackColor = $script:UiCard
        $c.ForeColor = $script:UiText
        $c.Font = $script:UiFontUi
      }
      elseif ($c -is [System.Windows.Forms.ComboBox]) {
        $c.FlatStyle = 'Flat'
        $c.Font = $script:UiFontUi
        $c.BackColor = $script:UiCard
        $c.ForeColor = $script:UiText
      }
      elseif ($c -is [System.Windows.Forms.ListBox] -or $c -is [System.Windows.Forms.CheckedListBox]) {
        $c.BorderStyle = 'FixedSingle'
        $c.BackColor = $script:UiCard
        $c.ForeColor = $script:UiText
        $c.Font = $script:UiFontUi
      }
      elseif ($c -is [System.Windows.Forms.CheckBox]) {
        $c.ForeColor = $script:UiText
        $c.Font = $script:UiFontUi
        $c.BackColor = [System.Drawing.Color]::Transparent
        $c.FlatStyle = 'Flat'
      }
      elseif ($c -is [System.Windows.Forms.DateTimePicker]) {
        $c.Font = $script:UiFontUi
        $c.CalendarForeColor = $script:UiText
      }
    } catch { }
    foreach ($ch in @($c.Controls)) { $queue.Enqueue($ch) }
  }
}

function Set-PenTheme {
  param([string]$Name, [switch]$Persist, [switch]$SkipRefresh)
  if (-not $Name) { $Name = 'black' }
  if (-not $script:ThemeDefs.Contains($Name)) { $Name = 'black' }
  $d = $script:ThemeDefs[$Name]
  $script:ThemeName = $Name
  $script:UiBg = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Bg)
  $script:UiCard = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Card)
  $script:UiTile = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Tile)
  $script:UiSidebar = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Sidebar)
  $script:UiAccentHex = [string]$d.Accent
  $script:UiAccent = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Accent)
  $script:UiAccentSoft = [System.Drawing.ColorTranslator]::FromHtml([string]$d.AccentSoft)
  $script:UiText = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Text)
  $script:UiMuted = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Muted)
  $script:UiBorder = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Border)
  $script:UiBtnSoft = $script:UiTile
  $script:UiDanger = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Danger)
  $script:UiSuccess = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Success)
  $script:UiHover = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Hover)
  $script:UiPressed = [System.Drawing.ColorTranslator]::FromHtml([string]$d.Pressed)
  $script:UiAccentHover = [System.Drawing.ColorTranslator]::FromHtml([string]$d.AccentHover)
  $script:UiAccentPressed = [System.Drawing.ColorTranslator]::FromHtml([string]$d.AccentPressed)
  $script:UiStatusBg = [System.Drawing.ColorTranslator]::FromHtml([string]$d.StatusBg)
  $script:UiHeaderBg = [System.Drawing.ColorTranslator]::FromHtml([string]$d.HeaderBg)
  $script:UiChipBg = [System.Drawing.ColorTranslator]::FromHtml([string]$d.ChipBg)

  if ($Persist) { Save-PenSettings -Theme $Name }

  if ($SkipRefresh) { return }

  if (Get-Variable -Name form -Scope Script -ErrorAction SilentlyContinue) {
    # fall through
  }
  try {
    if ($form) {
      Apply-AppleTheme -Root $form
      # shell chrome
      if ($pnlSidebar) {
        $pnlSidebar.BackColor = $script:UiSidebar
        $pnlSidebar.Tag = 'sidebar'
      }
      if ($lblBrand) {
        $lblBrand.BackColor = $script:UiSidebar
        $lblBrand.ForeColor = $script:UiText
      }
      if ($flowNav) { $flowNav.BackColor = $script:UiSidebar; $flowNav.Tag = 'sidebar' }
      if ($pnlStatusBar) {
        $pnlStatusBar.BackColor = $script:UiStatusBg
        $pnlStatusBar.ForeColor = $script:UiMuted
        $pnlStatusBar.Tag = 'statusbar'
      }
      if ($pnlHeader) {
        $pnlHeader.BackColor = $script:UiHeaderBg
        $pnlHeader.Tag = 'header'
      }
      if ($pnlContent) { $pnlContent.BackColor = $script:UiBg }
      # refresh nav selection
      if ($script:CurrentPage) { Show-PenPage -Key $script:CurrentPage }
      if ($script:LblThemeNow) {
        $script:LblThemeNow.Text = ('현재 테마: {0}' -f $d.Label)
        $script:LblThemeNow.ForeColor = $script:UiText
      }
      if (Get-Command Refresh-UnifiedWorkList -ErrorAction SilentlyContinue) {
        try { Refresh-UnifiedWorkList } catch { }
      }
      if ($fitHome) { try { & $fitHome } catch { } }
      if (Get-Variable -Name NoticeFitChrome -Scope Script -ErrorAction SilentlyContinue) {
        if ($script:NoticeFitChrome) { try { & $script:NoticeFitChrome } catch { } }
      }
      if (Get-Variable -Name TripFitChrome -Scope Script -ErrorAction SilentlyContinue) {
        if ($script:TripFitChrome) { try { & $script:TripFitChrome } catch { } }
      }
      if ($lblStatus) { $lblStatus.Text = ('테마: {0} · 상신 안 함' -f $d.Label) }
    }
  } catch {
    Write-Host ('Set-PenTheme refresh: ' + $_.Exception.Message)
  }
}

# load saved theme (colors only until UI exists)
try {
  $boot = Get-PenSettings
  Set-PenTheme -Name $boot.Theme -SkipRefresh
} catch {
  Set-PenTheme -Name 'black' -SkipRefresh
}

# ---------- UI ----------
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.Size = New-Object System.Drawing.Size(980, 760)
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = $script:UiFontUi
$form.BackColor = $script:UiBg
$form.ForeColor = $script:UiText

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = $script:AppName
$notify.Visible = $true

$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $ctx.Items.Add('창 열기')
$miExit = $ctx.Items.Add('종료')
$notify.ContextMenuStrip = $ctx

$script:ReallyExit = $false
$miShow.add_Click({
    $form.Show()
    $form.WindowState = 'Normal'
    $form.Activate()
})
$miExit.add_Click({
    $script:ReallyExit = $true
    $notify.Visible = $false
    $form.Close()
})
$notify.add_DoubleClick({
    $form.Show()
    $form.WindowState = 'Normal'
    $form.Activate()
})
$form.add_FormClosing({
    param($sender, $e)
    if (-not $script:ReallyExit) {
        $e.Cancel = $true
        $form.Hide()
        $notify.ShowBalloonTip(2000, $script:AppName, '트레이로 최소화했습니다.', 'Info')
    }
})

# ===== Sidebar shell =====
$pnlSidebar = New-Object System.Windows.Forms.Panel
$pnlSidebar.Dock = 'Left'
$pnlSidebar.Width = 168
$pnlSidebar.BackColor = $script:UiSidebar
$pnlSidebar.Padding = New-Object System.Windows.Forms.Padding(6)
$pnlSidebar.Tag = 'sidebar'

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "PEN`n도우미"
$lblBrand.ForeColor = $script:UiText
$lblBrand.Font = New-Object System.Drawing.Font('맑은 고딕', 13, [System.Drawing.FontStyle]::Bold)
$lblBrand.AutoSize = $false
$lblBrand.Height = 52
$lblBrand.Dock = 'Top'
$lblBrand.TextAlign = 'MiddleLeft'
$lblBrand.Padding = New-Object System.Windows.Forms.Padding(6, 6, 6, 4)
$lblBrand.BackColor = $script:UiSidebar

$flowNav = New-Object System.Windows.Forms.FlowLayoutPanel
$flowNav.Dock = 'Fill'
$flowNav.FlowDirection = 'TopDown'
$flowNav.WrapContents = $false
$flowNav.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
$flowNav.BackColor = $script:UiSidebar
$flowNav.Tag = 'sidebar'

$script:NavButtons = @{}
$script:Pages = @{}
$script:CurrentPage = 'home'

function New-NavButton([string]$Key, [string]$Text) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $Text
  $b.Width = 152
  $b.Height = 40
  $b.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 0
  $b.Font = $script:UiFontBtn
  $b.ForeColor = $script:UiText
  $b.BackColor = $script:UiSidebar
  $b.TextAlign = 'MiddleLeft'
  $b.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.Tag = $Key
  $b.MinimumSize = New-Object System.Drawing.Size(140, 36)
  $b.add_Click({
    param($s, $e)
    Show-PenPage -Key ([string]$s.Tag)
  })
  return $b
}

foreach ($pair in @(
  @{ K='home'; T='■  바로가기' },
  @{ K='notice'; T='▣  안내공문' },
  @{ K='trip'; T='▲  출장신청' },
  @{ K='todo'; T='▦  할 일·일정' },
  @{ K='settings'; T='⚙  설정' }
)) {
  $nb = New-NavButton $pair.K $pair.T
  [void]$flowNav.Controls.Add($nb)
  $script:NavButtons[$pair.K] = $nb
}

[void]$pnlSidebar.Controls.Add($flowNav)
[void]$pnlSidebar.Controls.Add($lblBrand)

$pnlStatusBar = New-Object System.Windows.Forms.Label
$pnlStatusBar.Dock = 'Bottom'
$pnlStatusBar.Height = 28
$pnlStatusBar.BackColor = $script:UiStatusBg
$pnlStatusBar.ForeColor = $script:UiMuted
$pnlStatusBar.Font = $script:UiFontCaption
$pnlStatusBar.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$pnlStatusBar.Tag = 'statusbar'
$pnlStatusBar.Text = '준비 중…'
$script:lblStatus = $pnlStatusBar
$lblStatus = $pnlStatusBar

$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Dock = 'Fill'
$pnlContent.BackColor = $script:UiBg
$pnlContent.Tag = 'bg'

function New-PagePanel([string]$Key) {
  $p = New-Object System.Windows.Forms.Panel
  $p.Dock = 'Fill'
  $p.BackColor = $script:UiBg
  $p.Tag = 'bg'
  $p.Visible = $false
  $script:Pages[$Key] = $p
  [void]$pnlContent.Controls.Add($p)
  return $p
}

function Show-PenPage {
  param([string]$Key)
  if (-not $script:Pages.ContainsKey($Key)) { return }
  foreach ($k in @($script:Pages.Keys)) {
    $script:Pages[$k].Visible = ($k -eq $Key)
  }
  $script:CurrentPage = $Key
  if ($Key -eq 'todo') {
    Refresh-UnifiedWorkList
  }
  if ($Key -eq 'home' -and $script:HomeScroll) {
    try { $script:HomeScroll.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) } catch { }
    try { & $fitHome } catch { }
  }
  foreach ($k in @($script:NavButtons.Keys)) {
    if ($k -eq $Key) {
      $script:NavButtons[$k].BackColor = $script:UiCard
      $script:NavButtons[$k].ForeColor = $script:UiAccent
      $script:NavButtons[$k].Font = $script:UiFontBtn
      Set-RoundedRegion -Control $script:NavButtons[$k] -Radius 12
    } else {
      $script:NavButtons[$k].BackColor = $script:UiSidebar
      $script:NavButtons[$k].ForeColor = $script:UiText
      $script:NavButtons[$k].Font = $script:UiFontBtn
      $script:NavButtons[$k].Region = $null
    }
  }
  if ($Key -eq 'notice' -and (Get-Variable -Name NoticeFitChrome -Scope Script -ErrorAction SilentlyContinue) -and $script:NoticeFitChrome) { & $script:NoticeFitChrome }
  if ($Key -eq 'trip' -and (Get-Variable -Name TripFitChrome -Scope Script -ErrorAction SilentlyContinue) -and $script:TripFitChrome) { & $script:TripFitChrome }
}

$pageHome = New-PagePanel 'home'
$pageNotice = New-PagePanel 'notice'
$pageTrip = New-PagePanel 'trip'
$pageTodo = New-PagePanel 'todo'
$pageSettings = New-PagePanel 'settings'

# header theme strip (Dock Top on form)
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 40
$pnlHeader.BackColor = $script:UiHeaderBg
$pnlHeader.Tag = 'header'
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(8,4,8,4)
$flowHeaderThemes = New-Object System.Windows.Forms.FlowLayoutPanel
$flowHeaderThemes.Dock = 'Fill'
$flowHeaderThemes.FlowDirection = 'LeftToRight'
$flowHeaderThemes.WrapContents = $false
$flowHeaderThemes.BackColor = $script:UiHeaderBg
$flowHeaderThemes.Tag = 'header'
$lblHdr = New-Object System.Windows.Forms.Label
$lblHdr.Text = '테마'
$lblHdr.AutoSize = $true
$lblHdr.Font = $script:UiFontSection
$lblHdr.ForeColor = $script:UiMuted
$lblHdr.Tag = 'section'
$lblHdr.Margin = New-Object System.Windows.Forms.Padding(0,8,8,0)
[void]$flowHeaderThemes.Controls.Add($lblHdr)
foreach ($tk in @('black','sky','pink','white')) {
  $td = $script:ThemeDefs[$tk]
  $hb = New-Object System.Windows.Forms.Button
  $hb.Name = ('theme_{0}' -f $tk)
  $hb.Text = [string]$td.Label
  $hb.Width = 64
  $hb.Height = 28
  $hb.Margin = New-Object System.Windows.Forms.Padding(0,2,4,0)
  $hb.FlatStyle = 'Flat'
  $hb.FlatAppearance.BorderSize = 0
  $hb.Font = $script:UiFontSection
  $hb.Cursor = [System.Windows.Forms.Cursors]::Hand
  $hb.MinimumSize = New-Object System.Drawing.Size(56, 28)
  $hb.add_Click({
    param($s,$e)
    $n = ([string]$s.Name) -replace '^theme_',''
    Set-PenTheme -Name $n -Persist
  })
  [void]$flowHeaderThemes.Controls.Add($hb)
}
[void]$pnlHeader.Controls.Add($flowHeaderThemes)

[void]$form.Controls.Add($pnlContent)
[void]$form.Controls.Add($pnlStatusBar)
[void]$form.Controls.Add($pnlHeader)
[void]$form.Controls.Add($pnlSidebar)

# --- HOME: calculator tiles for shortcuts + alerts ---
$homeScroll = New-Object System.Windows.Forms.Panel
$homeScroll.Dock = 'Fill'
$homeScroll.AutoScroll = $true
$homeScroll.BackColor = $script:UiBg
$homeScroll.Tag = 'bg'
$homeScroll.Padding = New-Object System.Windows.Forms.Padding(8)

$cardHomeTiles = New-Object System.Windows.Forms.Panel
$cardHomeTiles.AutoSize = $true
$cardHomeTiles.Padding = New-Object System.Windows.Forms.Padding(8)
$cardHomeTiles.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$cardHomeTiles.BackColor = [System.Drawing.Color]::White
$cardHomeTiles.Tag = 'card'
$cardHomeTiles.add_Paint({
  param($s,$e)
  $pen = New-Object System.Drawing.Pen ($script:UiBorder), 1
  $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
  $pen.Dispose()
})
$lblHomeHead = New-Object System.Windows.Forms.Label
$lblHomeHead.Text = '바로가기'
$lblHomeHead.Font = $script:UiFontTitle
$lblHomeHead.AutoSize = $true
$lblHomeHead.Tag = 'stephead'
$lblHomeHead.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)
$gridHome = New-Object System.Windows.Forms.FlowLayoutPanel
$gridHome.AutoSize = $true
$gridHome.WrapContents = $true
$gridHome.BackColor = [System.Drawing.Color]::White
$gridHome.Tag = 'card'

$script:BtnMap = @{}
$script:BtnUrlMap = @{}
$homeTips = @{
  '결재대기' = '결재대기 화면을 엽니다'
  '문서진행' = '문서진행 화면을 엽니다'
  '공람' = '공람대기 화면을 엽니다'
  '발송대기' = '발송대기 화면을 엽니다'
  '공문접수' = '공문접수 + 과제카드 Top3 추천 (저장/접수 안 함)'
  '업무포털' = '업무포털을 엽니다'
}
$homeEmoji = @{
  '결재대기' = '●'
  '문서진행' = '■'
  '공람' = '◎'
  '발송대기' = '▲'
  '공문접수' = '◇'
  '업무포털' = '◆'
}
$homeTipCtrl = New-Object System.Windows.Forms.ToolTip
foreach ($name in $script:Urls.Keys) {
  $b = New-Object System.Windows.Forms.Button
  $em = $homeEmoji[$name]
  if (-not $em) { $em = '·' }
  $b.Text = ("{0}`r`n{1}" -f $em, $name)
  $b.Size = New-Object System.Drawing.Size(110, 80)
  $b.Margin = New-Object System.Windows.Forms.Padding(4)
  $b.FlatStyle = 'Flat'
  $b.Font = $script:UiFontBtn
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.UseVisualStyleBackColor = $false
  $b.Tag = 'uicolor:#E5E5EA;tile;radius12'
  $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
  $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $b.FlatAppearance.BorderSize = 0
  $b.TextAlign = 'MiddleCenter'
  if ($name -eq '결재대기') {
    $b.Name = 'badge:FF3B30'
    $b.add_Paint({
      param($s, $e)
      $col = [System.Drawing.ColorTranslator]::FromHtml('#FF3B30')
      $brush = New-Object System.Drawing.SolidBrush $col
      $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
      $e.Graphics.FillEllipse($brush, $s.Width - 22, 10, 10, 10)
      $brush.Dispose()
    })
  }
  $script:BtnUrlMap[$name] = $script:Urls[$name]
  $homeTipCtrl.SetToolTip($b, [string]$homeTips[$name])
  $null = $b.add_Click({
    param($sender, $e)
    foreach ($k in @($script:BtnUrlMap.Keys)) {
      if ($script:BtnMap.ContainsKey($k) -and [object]::ReferenceEquals($script:BtnMap[$k], $sender)) {
        if ($k -eq '공문접수') {
          Open-InChrome -Url $script:BtnUrlMap[$k]
          if (Get-Command Invoke-GongmunRecvAssist -ErrorAction SilentlyContinue) {
            $rr = Invoke-GongmunRecvAssist
            if ($lblStatus) { $lblStatus.Text = $rr.Message }
          }
        } else {
          Open-InChrome -Url $script:BtnUrlMap[$k]
        }
        break
      }
    }
  })
  [void]$gridHome.Controls.Add($b)
  $script:BtnMap[$name] = $b
}
$innerHome = New-Object System.Windows.Forms.FlowLayoutPanel
$innerHome.FlowDirection = 'TopDown'; $innerHome.AutoSize = $true; $innerHome.WrapContents = $false
$innerHome.BackColor = [System.Drawing.Color]::White; $innerHome.Tag = 'card'
[void]$innerHome.Controls.Add($lblHomeHead)
[void]$innerHome.Controls.Add($gridHome)
[void]$cardHomeTiles.Controls.Add($innerHome)

$cardAlert = New-Object System.Windows.Forms.Panel
$cardAlert.AutoSize = $false
$cardAlert.Height = 320
$cardAlert.Padding = New-Object System.Windows.Forms.Padding(8)
$cardAlert.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$cardAlert.BackColor = [System.Drawing.Color]::White
$cardAlert.Tag = 'card'
$cardAlert.add_Paint({
  param($s,$e)
  $pen = New-Object System.Drawing.Pen ($script:UiBorder), 1
  $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
  $pen.Dispose()
})
$lblAlertHead = New-Object System.Windows.Forms.Label
$lblAlertHead.Text = '최근 알림'
$lblAlertHead.Font = $script:UiFontTitle
$lblAlertHead.AutoSize = $true
$lblAlertHead.Dock = 'Top'
$lblAlertHead.Tag = 'stephead'
$lblAlertHead.Padding = New-Object System.Windows.Forms.Padding(0,0,0,8)

$lstAlerts = New-Object System.Windows.Forms.ListBox
$lstAlerts.Dock = 'Fill'
$lstAlerts.IntegralHeight = $false
$lstAlerts.HorizontalScrollbar = $true
$lstAlerts.Font = New-Object System.Drawing.Font('맑은 고딕', 11)

$pnlAlertAct = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlAlertAct.Dock = 'Bottom'
$pnlAlertAct.Height = 52
$pnlAlertAct.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$pnlAlertAct.BackColor = [System.Drawing.Color]::White
$pnlAlertAct.Tag = 'card'

$btnOpenRelated = New-Object System.Windows.Forms.Button
$btnOpenRelated.Text = "▸ 관련화면"
$btnOpenRelated.Size = New-Object System.Drawing.Size(110, 80)
# keep smaller row button
$btnOpenRelated.Size = New-Object System.Drawing.Size(150, 40)
$btnOpenRelated.FlatStyle = 'Flat'
$btnOpenRelated.Font = $script:UiFontBtn
$btnOpenRelated.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
$btnOpenRelated.ForeColor = [System.Drawing.Color]::White
$btnOpenRelated.FlatAppearance.BorderSize = 0
$btnOpenRelated.Tag = 'uicolor:#007AFF'
$btnOpenRelated.Cursor = [System.Windows.Forms.Cursors]::Hand
$homeTipCtrl.SetToolTip($btnOpenRelated, '선택 알림과 관련된 포털 화면을 엽니다 (할 일/공문 자동생성 없음)')
[void]$pnlAlertAct.Controls.Add($btnOpenRelated)

[void]$cardAlert.Controls.Add($lstAlerts)
[void]$cardAlert.Controls.Add($pnlAlertAct)
[void]$cardAlert.Controls.Add($lblAlertHead)

# --- extras: status chips + tools-review features ---
$cardExtras = New-Object System.Windows.Forms.Panel
$cardExtras.AutoSize = $false
$cardExtras.Height = 220
$cardExtras.Padding = New-Object System.Windows.Forms.Padding(8)
$cardExtras.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
$cardExtras.BackColor = [System.Drawing.Color]::White
$cardExtras.Tag = 'card'
$cardExtras.add_Paint({
  param($s,$e)
  $pen = New-Object System.Drawing.Pen ($script:UiBorder), 1
  $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
  $pen.Dispose()
})
$innerEx = New-Object System.Windows.Forms.FlowLayoutPanel
$innerEx.FlowDirection = 'TopDown'
$innerEx.AutoSize = $true
$innerEx.WrapContents = $false
$innerEx.Dock = 'Top'
$innerEx.BackColor = [System.Drawing.Color]::White
$innerEx.Tag = 'card'
$lblExHead = New-Object System.Windows.Forms.Label
$lblExHead.Text = '도구 · 상태'
$lblExHead.Font = $script:UiFontTitle
$lblExHead.AutoSize = $true
$lblExHead.Tag = 'stephead'
$lblExHead.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)
$lblSafety = New-Object System.Windows.Forms.Label
$lblSafety.Text = '상신 안 함  ·  저장/결재올림/발송 자동 클릭 없음'
$lblSafety.AutoSize = $true
$lblSafety.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#FF3B30')
$lblSafety.Font = $script:UiFontSection
$lblSafety.Tag = 'safety'
$lblSafety.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)
$lblChips = New-Object System.Windows.Forms.Label
$lblChips.Name = 'statusChips'
$lblChips.AutoSize = $true
$lblChips.ForeColor = $script:UiMuted
$lblChips.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
$lblChips.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
$script:LblStatusChips = $lblChips
$gridEx = New-Object System.Windows.Forms.FlowLayoutPanel
$gridEx.AutoSize = $true
$gridEx.WrapContents = $true
$gridEx.BackColor = [System.Drawing.Color]::White
$gridEx.Tag = 'card'
function New-ExTile([string]$Text, [string]$Tip) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $Text
  $b.Size = New-Object System.Drawing.Size(110, 72)
  $b.Margin = New-Object System.Windows.Forms.Padding(4)
  $b.FlatStyle = 'Flat'
  $b.Font = $script:UiFontBtn
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.Tag = 'uicolor:#E5E5EA;tile;radius12'
  $b.BackColor = $script:UiTile
  $b.ForeColor = $script:UiText
  $b.FlatAppearance.BorderSize = 0
  $b.TextAlign = 'MiddleCenter'
  $b.MinimumSize = New-Object System.Drawing.Size(100, 44)
  if ($Tip) { $homeTipCtrl.SetToolTip($b, $Tip) }
  return $b
}
$btnExRelated = New-ExTile ("관련문서`n복사") '클립보드/선택 알림 → 관련문서번호 형식 복사 (상신 안 함)'
$btnExKeep = New-ExTile ("세션유지`nON") '업무포털 세션 유지 URL 열기 (로그인·상신은 사용자)'
$btnExBadge = New-ExTile ("배지`n새로고침") 'Chrome 창에서 결재/공람 건수 힌트 읽기'
$btnExGong = New-ExTile ("공람→`n할 일") '클립보드 공람 원문에서 조치·기한 추출 → 할 일'
$btnExTravel = New-ExTile ("여비정산`n이어가기") 'neis.me 여비정산 열기 + 힌트 복사 (제출 안 함)'
$btnExRecv = New-ExTile ("공문접수`n과제카드") '제목/본문 키워드 → 과제카드 Top3 추천·필드 채우기 (저장/접수 안 함)'
foreach ($bx in @($btnExRelated, $btnExKeep, $btnExBadge, $btnExGong, $btnExTravel, $btnExRecv)) { [void]$gridEx.Controls.Add($bx) }
$lblDuty = New-Object System.Windows.Forms.Label
$lblDuty.Text = '복무 프리셋 (채우기만)'
$lblDuty.AutoSize = $true
$lblDuty.ForeColor = $script:UiMuted
$lblDuty.Margin = New-Object System.Windows.Forms.Padding(0,8,0,4)
$gridDuty = New-Object System.Windows.Forms.FlowLayoutPanel
$gridDuty.AutoSize = $true
$gridDuty.WrapContents = $true
$gridDuty.BackColor = [System.Drawing.Color]::White
$gridDuty.Tag = 'card'
$script:DutyButtons = @{}
if (Get-Command Get-DutyPresets -ErrorAction SilentlyContinue) {
  foreach ($dp in @(Get-DutyPresets)) {
    $db = New-ExTile ([string]$dp.Label) ('복무 ' + $dp.Label + ' 값 복사·포털 열기 (상신 안 함)')
    $db.Name = ('duty_' + [string]$dp.Key)
    $db.Tag = 'uicolor:#E5E5EA;tile;radius12'
    $db.add_Click({
      param($sender, $e)
      $key = ([string]$sender.Name) -replace '^duty_',''
      if (Get-Command Invoke-DutyPresetFill -ErrorAction SilentlyContinue) {
        $rr = Invoke-DutyPresetFill -Key $key
        $lblStatus.Text = $rr.Message
        if ($script:LblStatusChips -and (Get-Command Get-StatusChipText -ErrorAction SilentlyContinue)) {
          $script:LblStatusChips.Text = Get-StatusChipText
        }
      }
    })
    [void]$gridDuty.Controls.Add($db)
    $script:DutyButtons[$dp.Key] = $db
  }
}
[void]$innerEx.Controls.Add($lblExHead)
[void]$innerEx.Controls.Add($lblSafety)
[void]$innerEx.Controls.Add($lblChips)
[void]$innerEx.Controls.Add($gridEx)
[void]$innerEx.Controls.Add($lblDuty)
[void]$innerEx.Controls.Add($gridDuty)
[void]$cardExtras.Controls.Add($innerEx)

$btnExRelated.add_Click({
  $raw = ''
  $a = Get-SelectedAlert
  if ($null -ne $a) { $raw = ("{0}`n{1}" -f $a.Title, $a.Body) }
  if (Get-Command Copy-RelatedDocumentNumber -ErrorAction SilentlyContinue) {
    $rr = Copy-RelatedDocumentNumber -RawText $raw
    $lblStatus.Text = $rr.Message
    if ($rr.Ok) { [System.Windows.Forms.MessageBox]::Show(('클립보드:`n{0}' -f $rr.Line), $script:AppName) | Out-Null }
    else { [System.Windows.Forms.MessageBox]::Show($rr.Message, $script:AppName) | Out-Null }
  }
})
$btnExKeep.add_Click({
  if (Get-Command Invoke-PortalKeepAlive -ErrorAction SilentlyContinue) {
    $rr = Invoke-PortalKeepAlive
    $lblStatus.Text = $rr.Message
    if ($script:LblStatusChips) { $script:LblStatusChips.Text = Get-StatusChipText }
  }
})
$btnExBadge.add_Click({
  if (Get-Command Refresh-PortalBadgesFromChrome -ErrorAction SilentlyContinue) {
    $rr = Refresh-PortalBadgesFromChrome
    $c = $rr.Counts
    $lblStatus.Text = ('배지 결재 {0} · 공람 {1} · 발송 {2}' -f $c['결재대기'], $c['공람'], $c['발송대기'])
    try {
      if ($script:BtnMap.ContainsKey('결재대기')) {
        $nb = [int]$c['결재대기']
        $script:BtnMap['결재대기'].Text = if ($nb -gt 0) { ("●`r`n결재대기 ({0})" -f $nb) } else { "●`r`n결재대기" }
      }
      if ($script:BtnMap.ContainsKey('공람')) {
        $nb = [int]$c['공람']
        $script:BtnMap['공람'].Text = if ($nb -gt 0) { ("◎`r`n공람 ({0})" -f $nb) } else { "◎`r`n공람" }
      }
    } catch { }
    if ($script:LblStatusChips) { $script:LblStatusChips.Text = Get-StatusChipText }
  }
})
$btnExGong.add_Click({
  if (Get-Command Import-GongramTextToTodos -ErrorAction SilentlyContinue) {
    $rr = Import-GongramTextToTodos
    $lblStatus.Text = $rr.Message
    Show-PenPage -Key 'todo'
  }
})
$btnExTravel.add_Click({
  if (Get-Command Start-TravelSettlementContinuation -ErrorAction SilentlyContinue) {
    $rr = Start-TravelSettlementContinuation
    $lblStatus.Text = $rr.Message
  }
})
$btnExRecv.add_Click({
  if (Get-Command Invoke-GongmunRecvAssist -ErrorAction SilentlyContinue) {
    if ($script:Urls.Contains('공문접수')) { Open-InChrome -Url $script:Urls['공문접수'] }
    $rr = Invoke-GongmunRecvAssist
    $lblStatus.Text = $rr.Message
  } else {
    [System.Windows.Forms.MessageBox]::Show('PenExtras 공문접수 모듈이 없습니다.', $script:AppName) | Out-Null
  }
})

$script:HomeCards = @($cardHomeTiles, $cardExtras, $cardAlert)

$script:HomeScroll = $homeScroll
# Dock Top = full content width
$cardAlert.Dock = 'Top'; $cardAlert.AutoSize = $false; $cardAlert.Height = 280
$cardExtras.Dock = 'Top'; $cardExtras.AutoSize = $false; $cardExtras.Height = 300
$cardHomeTiles.Dock = 'Top'; $cardHomeTiles.AutoSize = $false; $cardHomeTiles.Height = 180
# Dock Top: last added sits at visual top → 바로가기 / 도구 / 알림
[void]$homeScroll.Controls.Add($cardAlert)
[void]$homeScroll.Controls.Add($cardExtras)
[void]$homeScroll.Controls.Add($cardHomeTiles)
[void]$pageHome.Controls.Add($homeScroll)
$fitHome = {
  try {
    $hostW = $script:HomeScroll.ClientSize.Width
    if ($hostW -le 40) { return }
    $iw = [Math]::Max(300, $hostW - 40)
    foreach ($c in @($script:HomeCards)) {
      if ($null -eq $c) { continue }
      $c.Dock = 'Top'
      $c.AutoSize = $false
      $c.Region = $null
      foreach ($ch in @($c.Controls)) {
        if ($ch -is [System.Windows.Forms.FlowLayoutPanel]) {
          $ch.Dock = 'Top'
          $ch.Width = $iw
          $ch.MaximumSize = New-Object System.Drawing.Size($iw, 100000)
          foreach ($g in @($ch.Controls)) {
            if ($g -is [System.Windows.Forms.FlowLayoutPanel]) {
              $g.Width = $iw
              $g.MaximumSize = New-Object System.Drawing.Size($iw, 100000)
            }
          }
        }
      }
    }
    # heights
    $inner0 = $null
    foreach ($ch in @($script:HomeCards[0].Controls)) { if ($ch -is [System.Windows.Forms.FlowLayoutPanel]) { $inner0 = $ch; break } }
    if ($null -ne $inner0) {
      $pref = $inner0.GetPreferredSize((New-Object System.Drawing.Size($iw, 0)))
      $script:HomeCards[0].Height = [Math]::Max(140, $pref.Height + 40)
    }
    if (@($script:HomeCards).Count -gt 1) {
      $pref1 = 200
      try {
        $inner1 = $null
        foreach ($ch in @($script:HomeCards[1].Controls)) { if ($ch -is [System.Windows.Forms.FlowLayoutPanel]) { $inner1 = $ch; break } }
        if ($null -ne $inner1) { $pref1 = $inner1.GetPreferredSize((New-Object System.Drawing.Size($iw, 0))).Height + 36 }
      } catch { }
      $script:HomeCards[1].Height = [Math]::Max(200, $pref1)
    }
    if (@($script:HomeCards).Count -gt 2) { $script:HomeCards[2].Height = 280 }
    foreach ($b in @($script:BtnMap.Values)) { Set-RoundedRegion -Control $b -Radius 12 }

  } catch { }
}
$homeScroll.add_Resize({ & $fitHome })

$script:AlertStore = New-Object System.Collections.Generic.List[object]

function Highlight-Button {
    param([string]$BtnName)
    foreach ($k in @($script:BtnMap.Keys)) {
        $b = $script:BtnMap[$k]
        $b.Tag = 'uicolor:#E5E5EA;tile;radius12'
        $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
        $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
        $b.FlatAppearance.BorderSize = 0
        Set-RoundedRegion -Control $b -Radius 12
    }
    if ($BtnName -and $script:BtnMap.ContainsKey($BtnName)) {
        $script:BtnMap[$BtnName].FlatAppearance.BorderSize = 2
        $script:BtnMap[$BtnName].FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
    }
}

function Refresh-AlertList {
    $lstAlerts.BeginUpdate()
    try {
        $lstAlerts.Items.Clear()
        foreach ($a in $script:AlertStore) {
            [void]$lstAlerts.Items.Add($a.Display)
        }
    } finally {
        $lstAlerts.EndUpdate()
    }
}

function Add-AlertItem {
    param($Title, $Body, $Category)
    $due = Get-DueDateFromText -Text ("{0}`n{1}" -f $Title, $Body)
    $cat = if ($Category) { '[{0}] ' -f $Category } else { '' }
    $dueTxt = if ($due) { ' (마감 {0})' -f $due } else { '' }
    $item = [pscustomobject]@{
        Time     = Get-Date -Format 'HH:mm:ss'
        Title    = $Title
        Body     = $Body
        Category = $Category
        Due      = $due
        Display  = '{0} {1}{2}{3}' -f (Get-Date -Format 'HH:mm:ss'), $cat, $Title, $dueTxt
    }
    $script:AlertStore.Insert(0, $item)
    while ($script:AlertStore.Count -gt 50) {
        [void]$script:AlertStore.RemoveAt($script:AlertStore.Count - 1)
    }
    Refresh-AlertList
    return $item
}

function Get-SelectedAlert {
    $i = $lstAlerts.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:AlertStore.Count) { return $null }
    return $script:AlertStore[$i]
}

# --- NOTICE / TRIP pages ---
if (Get-Command Add-NoticePage -ErrorAction SilentlyContinue) {
  try { Add-NoticePage -HostPanel $pageNotice } catch {
    [System.Windows.Forms.MessageBox]::Show(('안내공문 페이지 실패: {0}' -f $_.Exception.Message), $script:AppName) | Out-Null
  }
}
if (Get-Command Add-TripPage -ErrorAction SilentlyContinue) {
  try { Add-TripPage -HostPanel $pageTrip } catch {
    [System.Windows.Forms.MessageBox]::Show(('출장신청 페이지 실패: {0}' -f $_.Exception.Message), $script:AppName) | Out-Null
  }
}

# --- TODO / 일정 unified list (no calendar grid) ---
$pnlTodoTop = New-Object System.Windows.Forms.Panel
$pnlTodoTop.Dock = 'Top'
$pnlTodoTop.Height = 96
$pnlTodoTop.Padding = New-Object System.Windows.Forms.Padding(8)
$pnlTodoTop.BackColor = [System.Drawing.Color]::White
$pnlTodoTop.Tag = 'card'

$txtTodoTitle = New-Object System.Windows.Forms.TextBox
$txtTodoTitle.Location = New-Object System.Drawing.Point(12, 12)
$txtTodoTitle.Width = 280
$txtTodoTitle.Font = $script:UiFontUi

$dtDue = New-Object System.Windows.Forms.DateTimePicker
$dtDue.Location = New-Object System.Drawing.Point(300, 12)
$dtDue.Width = 130
$dtDue.Format = 'Short'
$dtDue.ShowCheckBox = $true
$dtDue.Checked = $false

$btnTodoAdd = New-Object System.Windows.Forms.Button
$btnTodoAdd.Text = '추가'
$btnTodoAdd.Location = New-Object System.Drawing.Point(440, 10)
$btnTodoAdd.Size = New-Object System.Drawing.Size(80, 36)
$btnTodoAdd.FlatStyle = 'Flat'
$btnTodoAdd.Tag = 'uicolor:#007AFF'
$btnTodoAdd.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
$btnTodoAdd.ForeColor = [System.Drawing.Color]::White
$btnTodoAdd.FlatAppearance.BorderSize = 0

$lblTodoHint = New-Object System.Windows.Forms.Label
$lblTodoHint.Text = '할 일·일정 · 날짜+내용 · 기한 지난/급한 항목이 위 · 상신 안 함'
$lblTodoHint.Location = New-Object System.Drawing.Point(12, 52)
$lblTodoHint.AutoSize = $true
$lblTodoHint.ForeColor = $script:UiMuted

[void]$pnlTodoTop.Controls.Add($txtTodoTitle)
[void]$pnlTodoTop.Controls.Add($dtDue)
[void]$pnlTodoTop.Controls.Add($btnTodoAdd)
[void]$pnlTodoTop.Controls.Add($lblTodoHint)

$pnlTodoBot = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlTodoBot.Dock = 'Bottom'
$pnlTodoBot.Height = 56
$pnlTodoBot.Padding = New-Object System.Windows.Forms.Padding(8)
$pnlTodoBot.BackColor = [System.Drawing.Color]::White
$pnlTodoBot.Tag = 'card'

$btnTodoDel = New-Object System.Windows.Forms.Button
$btnTodoDel.Text = '삭제'
$btnTodoDel.Size = New-Object System.Drawing.Size(90, 36)
$btnTodoDel.FlatStyle = 'Flat'
$btnTodoDel.Tag = 'uicolor:#8E8E93;outline'

$btnTodoOpen = New-Object System.Windows.Forms.Button
$btnTodoOpen.Text = '업무포털'
$btnTodoOpen.Size = New-Object System.Drawing.Size(100, 36)
$btnTodoOpen.FlatStyle = 'Flat'
$btnTodoOpen.Tag = 'uicolor:#007AFF'

$btnTodoGongram = New-Object System.Windows.Forms.Button
$btnTodoGongram.Text = '공람→할 일'
$btnTodoGongram.Size = New-Object System.Drawing.Size(120, 36)
$btnTodoGongram.FlatStyle = 'Flat'
$btnTodoGongram.Tag = 'uicolor:#E5E5EA;tile'
$btnTodoGongram.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')

$btnTodoRelated = New-Object System.Windows.Forms.Button
$btnTodoRelated.Text = '관련문서복사'
$btnTodoRelated.Size = New-Object System.Drawing.Size(120, 36)
$btnTodoRelated.FlatStyle = 'Flat'
$btnTodoRelated.Tag = 'uicolor:#E5E5EA;tile'
$btnTodoRelated.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')

[void]$pnlTodoBot.Controls.Add($btnTodoDel)
[void]$pnlTodoBot.Controls.Add($btnTodoGongram)
[void]$pnlTodoBot.Controls.Add($btnTodoRelated)
[void]$pnlTodoBot.Controls.Add($btnTodoOpen)

$scrollWork = New-Object System.Windows.Forms.Panel
$scrollWork.Dock = 'Fill'
$scrollWork.AutoScroll = $true
$scrollWork.BackColor = $script:UiBg
$scrollWork.Padding = New-Object System.Windows.Forms.Padding(8)
$scrollWork.Tag = 'bg'

$flowWork = New-Object System.Windows.Forms.FlowLayoutPanel
$flowWork.Dock = 'Top'
$flowWork.AutoSize = $true
$flowWork.FlowDirection = 'TopDown'
$flowWork.WrapContents = $false
$flowWork.BackColor = $script:UiBg
$flowWork.Tag = 'bg'
$flowWork.Padding = New-Object System.Windows.Forms.Padding(4)
[void]$scrollWork.Controls.Add($flowWork)

[void]$pageTodo.Controls.Add($scrollWork)
[void]$pageTodo.Controls.Add($pnlTodoBot)
[void]$pageTodo.Controls.Add($pnlTodoTop)
$script:FlowWork = $flowWork
$script:ScrollWork = $scrollWork
$script:FlowSched = $flowWork
$script:ScrollSched = $scrollWork
$script:SelectedWorkId = $null

$script:TodoList = New-Object System.Collections.Generic.List[object]
$script:SuppressTodoCheck = $false

function Persist-Todos {
    $arr = @()
    foreach ($t in $script:TodoList) {
        $arr += [pscustomobject]@{
            Id      = $t.Id
            Title   = $t.Title
            Body    = $t.Body
            Due     = $t.Due
            Done    = [bool]$t.Done
            Source  = $t.Source
            Created = $t.Created
            SchedId = $(if ($t.PSObject.Properties.Name -contains 'SchedId') { $t.SchedId } else { $null })
        }
    }
    Save-Todos -Todos $arr
}

function Add-TodoItem {
    param(
        [string]$Title,
        [string]$Body = '',
        [string]$Due = $null,
        [string]$Source = 'manual'
    )
    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    $item = [pscustomobject]@{
        Id      = [guid]::NewGuid().ToString('N')
        Title   = $Title.Trim()
        Body    = $Body
        Due     = $Due
        Done    = $false
        Source  = $Source
        Created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        SchedId = $null
    }
    $script:TodoList.Insert(0, $item)
    Persist-Todos
    Refresh-UnifiedWorkList
}

function Load-TodosIntoUi {
    $script:TodoList.Clear()
    foreach ($t in (Get-Todos)) {
        [void]$script:TodoList.Add([pscustomobject]@{
            Id      = $(if ($t.Id) { [string]$t.Id } else { [guid]::NewGuid().ToString('N') })
            Title   = [string]$t.Title
            Body    = $(if ($t.Body) { [string]$t.Body } else { '' })
            Due     = $(if ($t.Due) { [string]$t.Due } else { $null })
            Done    = [bool]($t.Done)
            Source  = $(if ($t.Source) { [string]$t.Source } else { 'manual' })
            Created = $(if ($t.Created) { [string]$t.Created } else { '' })
            SchedId = $(if ($t.PSObject.Properties.Name -contains 'SchedId' -and $t.SchedId) { [string]$t.SchedId } else { $null })
        })
    }
    Refresh-UnifiedWorkList
}

$script:ScheduleList = New-Object System.Collections.Generic.List[object]

function Get-Schedules {
    $data = Read-JsonFile -Path $script:SchedulesPath -Default @()
    if ($null -eq $data) { return @() }
    if ($data -isnot [System.Array]) { return @($data) }
    return @($data)
}

function Persist-Schedules {
    $arr = @()
    foreach ($s in $script:ScheduleList) {
        $arr += [pscustomobject]@{
            Id            = $s.Id
            Title         = $s.Title
            Body          = $s.Body
            Date          = $s.Date
            Source        = $s.Source
            Created       = $s.Created
            GoogleSaved   = [bool]$s.GoogleSaved
            TodoId        = $(if ($s.PSObject.Properties.Name -contains 'TodoId') { $s.TodoId } else { $null })
        }
    }
    Write-JsonFile -Path $script:SchedulesPath -Object @($arr)
}

function Load-SchedulesIntoUi {
    $script:ScheduleList.Clear()
    $savedMap = @{}
    if (Get-Command Get-GCalSavedMap -ErrorAction SilentlyContinue) {
        $savedMap = Get-GCalSavedMap
    }
    foreach ($s in (Get-Schedules)) {
        $id = $(if ($s.Id) { [string]$s.Id } else { [guid]::NewGuid().ToString('N') })
        $gSaved = [bool]($s.GoogleSaved)
        if (-not $gSaved -and $savedMap.ContainsKey($id)) { $gSaved = $true }
        [void]$script:ScheduleList.Add([pscustomobject]@{
            Id          = $id
            Title       = [string]$s.Title
            Body        = $(if ($s.Body) { [string]$s.Body } else { '' })
            Date        = $(if ($s.Date) { [string]$s.Date } else { '' })
            Source      = $(if ($s.Source) { [string]$s.Source } else { 'manual' })
            Created     = $(if ($s.Created) { [string]$s.Created } else { '' })
            GoogleSaved = $gSaved
            TodoId      = $(if ($s.PSObject.Properties.Name -contains 'TodoId' -and $s.TodoId) { [string]$s.TodoId } else { $null })
        })
    }
    Refresh-UnifiedWorkList
}

function Add-ScheduleItem {
    param([string]$Title, [string]$Body = '', [string]$Date = '', [string]$Source = 'manual', [string]$TodoId = $null)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Date)) { $Date = (Get-Date).ToString('yyyy-MM-dd') }
    $item = [pscustomobject]@{
        Id          = [guid]::NewGuid().ToString('N')
        Title       = $Title.Trim()
        Body        = $Body
        Date        = $Date
        Source      = $Source
        Created     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        GoogleSaved = $false
        TodoId      = $TodoId
    }
    $script:ScheduleList.Insert(0, $item)
    Persist-Schedules
    Refresh-UnifiedWorkList
    return $item
}

function Get-WorkSortKey {
    param($Due, [bool]$Done)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($Done) { return "9|$Due|z" }
    if ([string]::IsNullOrWhiteSpace($Due)) { return "2|9999-12-31|a" }
    if ($Due -lt $today) { return "0|$Due|a" }
    return "1|$Due|a"
}

function Ensure-ScheduleForTodo {
    param($Todo)
    if ($null -eq $Todo) { return $null }
    if ($Todo.SchedId) {
        foreach ($s in @($script:ScheduleList.ToArray())) {
            if ($s.Id -eq $Todo.SchedId) { return $s }
        }
    }
    foreach ($s in @($script:ScheduleList.ToArray())) {
        if ($s.TodoId -eq $Todo.Id) {
            $Todo.SchedId = $s.Id
            Persist-Todos
            return $s
        }
    }
    $due = if ($Todo.Due) { [string]$Todo.Due } else { (Get-Date).ToString('yyyy-MM-dd') }
    $sched = Add-ScheduleItem -Title $Todo.Title -Body $Todo.Body -Date $due -Source 'todo' -TodoId $Todo.Id
    if ($null -ne $sched) {
        $Todo.SchedId = $sched.Id
        Persist-Todos
    }
    return $sched
}

function Refresh-Calendar { Refresh-UnifiedWorkList }

function Refresh-UnifiedWorkList {
    if ($null -eq $script:FlowWork) { return }
    $flow = $script:FlowWork
    $flow.SuspendLayout()
    $flow.Controls.Clear()
    try {
        $rows = New-Object System.Collections.ArrayList
        $linkedSched = @{}
        foreach ($t in @($script:TodoList.ToArray())) {
            $sched = $null
            if ($t.SchedId) {
                foreach ($s in @($script:ScheduleList.ToArray())) { if ($s.Id -eq $t.SchedId) { $sched = $s; break } }
            }
            if ($null -eq $sched) {
                foreach ($s in @($script:ScheduleList.ToArray())) {
                    if ($s.TodoId -eq $t.Id) { $sched = $s; $t.SchedId = $s.Id; break }
                }
            }
            if ($null -ne $sched) { $linkedSched[$sched.Id] = $true }
            $due = if ($t.Due) { [string]$t.Due } elseif ($sched -and $sched.Date) { [string]$sched.Date } else { '' }
            [void]$rows.Add([pscustomobject]@{
                Kind='todo'; Todo=$t; Sched=$sched; Due=$due; Title=$t.Title; Done=[bool]$t.Done; Id=$t.Id
            })
        }
        foreach ($s in @($script:ScheduleList.ToArray())) {
            if ($linkedSched.ContainsKey($s.Id)) { continue }
            [void]$rows.Add([pscustomobject]@{
                Kind='sched'; Todo=$null; Sched=$s; Due=$(if ($s.Date) { $s.Date } else { '' }); Title=$s.Title; Done=$false; Id=$s.Id
            })
        }
        $sorted = @($rows | Sort-Object { Get-WorkSortKey -Due $_.Due -Done $_.Done }, Title)
        if (@($sorted).Count -eq 0) {
            $empty = New-Object System.Windows.Forms.Label
            $empty.Text = '할 일·일정이 없습니다. 위에서 추가하세요.'
            $empty.AutoSize = $true
            $empty.ForeColor = $script:UiMuted
            $empty.Margin = New-Object System.Windows.Forms.Padding(8)
            [void]$flow.Controls.Add($empty)
            return
        }
        $hostW = 520
        try {
            if ($script:ScrollWork -and $script:ScrollWork.ClientSize.Width -gt 80) {
                $hostW = [Math]::Max(360, $script:ScrollWork.ClientSize.Width - 28)
            }
        } catch { }
        $today = (Get-Date).ToString('yyyy-MM-dd')
        foreach ($r in $sorted) {
            $innerW = [Math]::Max(240, $hostW - 24)
            $row = New-Object System.Windows.Forms.Panel
            $row.Width = $hostW
            $row.Height = 118
            $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
            $row.BackColor = [System.Drawing.Color]::White
            $row.Tag = 'card'
            $row.Region = $null
            $row.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
            $row.add_Paint({
                param($sender, $e)
                $pen = New-Object System.Drawing.Pen ($script:UiBorder), 1
                $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
                $pen.Dispose()
            })

            $dateTxt = if ($r.Due) { $r.Due } else { '(날짜없음)' }
            $urgent = ($r.Due -and -not $r.Done -and $r.Due -lt $today)
            $lblDate = New-Object System.Windows.Forms.Label
            $lblDate.Text = $(if ($urgent) { '⚠ ' + $dateTxt + ' · 기한지남' } elseif ($r.Done) { $dateTxt + ' · 완료' } else { $dateTxt })
            $lblDate.Location = New-Object System.Drawing.Point(10, 6)
            $lblDate.AutoSize = $true
            $lblDate.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
            $lblDate.ForeColor = $(if ($urgent) { [System.Drawing.ColorTranslator]::FromHtml('#FF3B30') } else { $script:UiMuted })

            $lblTitle = New-Object System.Windows.Forms.Label
            $lblTitle.Text = $r.Title
            $lblTitle.Location = New-Object System.Drawing.Point(10, 28)
            $lblTitle.Size = New-Object System.Drawing.Size($innerW, 22)
            $lblTitle.Font = $script:UiFontUi
            $lblTitle.ForeColor = $script:UiText
            $lblTitle.Tag = $r.Id
            $lblTitle.add_Click({
                param($s2,$e2)
                $script:SelectedWorkId = [string]$s2.Tag
            })

            $btnW = [Math]::Min(140, [Math]::Max(110, [int](($innerW - 12) / 2)))
            $btnSched = New-Object System.Windows.Forms.Button
            $btnSched.Size = New-Object System.Drawing.Size($btnW, 32)
            $btnSched.Location = New-Object System.Drawing.Point(10, 58)
            $btnSched.FlatStyle = 'Flat'
            $btnSched.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
            $btnSched.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnSched.Text = '일정으로 등록'
            $btnSched.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
            $btnSched.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
            $btnSched.FlatAppearance.BorderSize = 0
            $btnSched.Tag = ('todo|' + $(if ($r.Todo) { $r.Todo.Id } else { '' }) + '|sched|' + $(if ($r.Sched) { $r.Sched.Id } else { '' }))
            if ($null -ne $r.Sched) {
                $btnSched.Text = '일정 등록됨'
                $btnSched.Enabled = $false
                $btnSched.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#34C759')
            } elseif ($null -eq $r.Todo) {
                $btnSched.Enabled = $false
                $btnSched.Text = '일정'
            } else {
                $btnSched.add_Click({
                    param($sender, $e)
                    $parts = ([string]$sender.Tag) -split '\|'
                    $tid = $parts[1]
                    $titem = $null
                    foreach ($x in @($script:TodoList.ToArray())) { if ($x.Id -eq $tid) { $titem = $x; break } }
                    if ($null -eq $titem) { return }
                    $sched = Ensure-ScheduleForTodo -Todo $titem
                    if ($null -ne $sched) {
                        $lblStatus.Text = ('일정 등록: {0} · {1}' -f $sched.Date, $sched.Title)
                    }
                    Refresh-UnifiedWorkList
                })
            }

            $btnG = New-Object System.Windows.Forms.Button
            $btnG.Size = New-Object System.Drawing.Size($btnW, 32)
            $btnG.Location = New-Object System.Drawing.Point((10 + $btnW + 8), 58)
            $btnG.FlatStyle = 'Flat'
            $btnG.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
            $btnG.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnG.Tag = ('todo|' + $(if ($r.Todo) { $r.Todo.Id } else { '' }) + '|sched|' + $(if ($r.Sched) { $r.Sched.Id } else { '' }))
            $alreadySaved = $false
            if ($r.Sched) {
                $alreadySaved = [bool]$r.Sched.GoogleSaved
                if (-not $alreadySaved -and (Get-Command Test-GCalItemSaved -ErrorAction SilentlyContinue)) {
                    if (Test-GCalItemSaved -ItemId $r.Sched.Id) { $alreadySaved = $true; $r.Sched.GoogleSaved = $true }
                }
            }
            if ($alreadySaved) {
                $btnG.Text = '구글 캘린더에 저장됨'
                $btnG.Width = [Math]::Min(180, $btnW + 40)
                $btnG.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
                $btnG.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#34C759')
                $btnG.FlatAppearance.BorderSize = 0
                $btnG.Enabled = $false
            } else {
                $btnG.Text = '구글 캘린더'
                $btnG.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
                $btnG.ForeColor = [System.Drawing.Color]::White
                $btnG.FlatAppearance.BorderSize = 0
                $btnG.add_Click({
                    param($sender, $e)
                    $parts = ([string]$sender.Tag) -split '\|'
                    $tid = $parts[1]; $sid = $parts[3]
                    $item = $null
                    if ($sid) {
                        foreach ($x in @($script:ScheduleList.ToArray())) { if ($x.Id -eq $sid) { $item = $x; break } }
                    }
                    if ($null -eq $item -and $tid) {
                        $titem = $null
                        foreach ($x in @($script:TodoList.ToArray())) { if ($x.Id -eq $tid) { $titem = $x; break } }
                        if ($null -ne $titem) { $item = Ensure-ScheduleForTodo -Todo $titem }
                    }
                    if ($null -eq $item) {
                        [System.Windows.Forms.MessageBox]::Show('일정 항목을 만들 수 없습니다.', $script:AppName) | Out-Null
                        return
                    }
                    $sender.Enabled = $false
                    $sender.Text = '저장 중…'
                    try {
                        if (-not (Get-Command Save-ScheduleToGoogleCalendar -ErrorAction SilentlyContinue)) {
                            [System.Windows.Forms.MessageBox]::Show('PenGoogleCal 모듈이 없습니다.', $script:AppName) | Out-Null
                            $sender.Text = '구글 캘린더'; $sender.Enabled = $true
                            return
                        }
                        $r2 = Save-ScheduleToGoogleCalendar -ItemId $item.Id -Title $item.Title -DateYmd $item.Date -Body $item.Body
                        if ($r2.Ok) {
                            $item.GoogleSaved = $true
                            Persist-Schedules
                            $lblStatus.Text = ('일정 저장 확인: {0} · {1}' -f $item.Date, $item.Title)
                            Refresh-UnifiedWorkList
                        } else {
                            $sender.Text = '구글 캘린더'
                            $sender.Enabled = $true
                            $msg = if ($r2.Message) { [string]$r2.Message } else { '저장 실패' }
                            if ($msg.Length -gt 800) { $msg = $msg.Substring(0, 800) + '…' }
                            [System.Windows.Forms.MessageBox]::Show($msg, $script:AppName) | Out-Null
                        }
                    } catch {
                        $sender.Text = '구글 캘린더'
                        $sender.Enabled = $true
                        [System.Windows.Forms.MessageBox]::Show(('오류: ' + $_.Exception.Message), $script:AppName) | Out-Null
                    }
                })
            }

            [void]$row.Controls.Add($lblDate)
            [void]$row.Controls.Add($lblTitle)
            [void]$row.Controls.Add($btnSched)
            [void]$row.Controls.Add($btnG)
            [void]$flow.Controls.Add($row)
        }
    } finally {
        $flow.ResumeLayout($true)
    }
}

# --- SETTINGS ---
$settingsScroll = New-Object System.Windows.Forms.Panel
$settingsScroll.Dock = 'Fill'
$settingsScroll.AutoScroll = $true
$settingsScroll.BackColor = $script:UiBg
$settingsScroll.Tag = 'bg'
$settingsScroll.Padding = New-Object System.Windows.Forms.Padding(8)
$settingsCard = New-Object System.Windows.Forms.Panel
$settingsCard.AutoSize = $true
$settingsCard.Padding = New-Object System.Windows.Forms.Padding(8)
$settingsCard.BackColor = $script:UiCard
$settingsCard.Tag = 'card'
$settingsInner = New-Object System.Windows.Forms.FlowLayoutPanel
$settingsInner.FlowDirection = 'TopDown'
$settingsInner.AutoSize = $true
$settingsInner.WrapContents = $false
$settingsInner.Dock = 'Top'
$settingsInner.BackColor = $script:UiCard
$settingsInner.Tag = 'card'
$lblSet = New-Object System.Windows.Forms.Label
$lblSet.Text = '설정'
$lblSet.Font = $script:UiFontTitle
$lblSet.AutoSize = $true
$lblSet.Tag = 'stephead'
$lblSet.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)

$lblThemeSec = New-Object System.Windows.Forms.Label
$lblThemeSec.Text = '테마'
$lblThemeSec.Font = $script:UiFontSection
$lblThemeSec.AutoSize = $true
$lblThemeSec.Tag = 'section'
$lblThemeSec.Margin = New-Object System.Windows.Forms.Padding(0,4,0,4)

$script:LblThemeNow = New-Object System.Windows.Forms.Label
$script:LblThemeNow.AutoSize = $true
$script:LblThemeNow.Font = $script:UiFontUi
$script:LblThemeNow.ForeColor = $script:UiText
$script:LblThemeNow.Text = ('현재 테마: {0}' -f $script:ThemeDefs[$script:ThemeName].Label)
$script:LblThemeNow.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)

$flowThemes = New-Object System.Windows.Forms.FlowLayoutPanel
$flowThemes.AutoSize = $true
$flowThemes.WrapContents = $true
$flowThemes.FlowDirection = 'LeftToRight'
$flowThemes.BackColor = $script:UiCard
$flowThemes.Tag = 'card'
$flowThemes.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$flowThemes.Padding = New-Object System.Windows.Forms.Padding(0)

foreach ($tk in @('black','sky','pink','white')) {
  $td = $script:ThemeDefs[$tk]
  $tb = New-Object System.Windows.Forms.Button
  $tb.Name = ('theme_{0}' -f $tk)
  $tb.Text = [string]$td.Label
  $tb.Width = 88
  $tb.Height = 36
  $tb.Margin = New-Object System.Windows.Forms.Padding(0,0,6,4)
  $tb.FlatStyle = 'Flat'
  $tb.FlatAppearance.BorderSize = 0
  $tb.Font = $script:UiFontBtn
  $tb.Cursor = [System.Windows.Forms.Cursors]::Hand
  $tb.MinimumSize = New-Object System.Drawing.Size(72, 36)
  $tb.add_Click({
    param($s,$e)
    $n = ([string]$s.Name) -replace '^theme_',''
    Set-PenTheme -Name $n -Persist
  })
  [void]$flowThemes.Controls.Add($tb)
}

$lblSetInfo = New-Object System.Windows.Forms.Label
$lblSetInfo.AutoSize = $true
$lblSetInfo.MaximumSize = New-Object System.Drawing.Size(700, 0)
$lblSetInfo.Font = $script:UiFontUi
$lblSetInfo.ForeColor = $script:UiText
$lblSetInfo.Text = "데이터: $script:DataDir`n초안: $script:DraftDir`n할 일·일정: 날짜+내용 목록(달력 없음), 기한지남·급한 순.`n[일정으로 등록]·[구글 캘린더] Chrome 템플릿→저장 클릭.`n관련문서복사·세션유지·공람→할 일·복무 프리셋·여비정산·공문접수(과제카드)는 채우기/열기만.`n결재올림/발송/상신/저장/접수/확인은 절대 클릭하지 않습니다. (상신 안 함)"
$lblSetInfo.Margin = New-Object System.Windows.Forms.Padding(0,8,0,0)

[void]$settingsInner.Controls.Add($lblSet)
[void]$settingsInner.Controls.Add($lblThemeSec)
[void]$settingsInner.Controls.Add($script:LblThemeNow)
[void]$settingsInner.Controls.Add($flowThemes)
[void]$settingsInner.Controls.Add($lblSetInfo)
[void]$settingsCard.Controls.Add($settingsInner)
[void]$settingsScroll.Controls.Add($settingsCard)
[void]$pageSettings.Controls.Add($settingsScroll)

# --- events ---
$btnOpenRelated.add_Click({
    $a = Get-SelectedAlert
    if ($null -eq $a) {
        [System.Windows.Forms.MessageBox]::Show('알림을 선택하세요.', $script:AppName) | Out-Null
        return
    }
    $btnName = '업무포털'
    if ($a.Category -and $script:KeywordToButton.ContainsKey([string]$a.Category)) {
        $btnName = $script:KeywordToButton[[string]$a.Category]
    }
    Open-InChrome -Url $script:Urls[$btnName]
    Highlight-Button -BtnName $btnName
})

$btnTodoAdd.add_Click({
    $title = $txtTodoTitle.Text
    if ([string]::IsNullOrWhiteSpace($title)) {
        [System.Windows.Forms.MessageBox]::Show('제목을 입력하세요.', $script:AppName) | Out-Null
        return
    }
    $due = $null
    if ($dtDue.Checked) { $due = $dtDue.Value.ToString('yyyy-MM-dd') }
    Add-TodoItem -Title $title -Due $due -Source 'manual'
    $txtTodoTitle.Text = ''
    $dtDue.Checked = $false
})

$btnTodoDel.add_Click({
    $id = $script:SelectedWorkId
    if (-not $id) {
        [System.Windows.Forms.MessageBox]::Show('삭제할 항목의 제목을 먼저 클릭해 선택하세요.', $script:AppName) | Out-Null
        return
    }
    $removed = $false
    for ($i = 0; $i -lt $script:TodoList.Count; $i++) {
        if ($script:TodoList[$i].Id -eq $id) {
            $script:TodoList.RemoveAt($i)
            Persist-Todos
            $removed = $true
            break
        }
    }
    if (-not $removed) {
        for ($i = 0; $i -lt $script:ScheduleList.Count; $i++) {
            if ($script:ScheduleList[$i].Id -eq $id) {
                $script:ScheduleList.RemoveAt($i)
                Persist-Schedules
                $removed = $true
                break
            }
        }
    }
    $script:SelectedWorkId = $null
    Refresh-UnifiedWorkList
})

$btnTodoOpen.add_Click({ Open-InChrome -Url $script:Urls['업무포털'] })

$btnTodoGongram.add_Click({
    if (-not (Get-Command Import-GongramTextToTodos -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show('PenExtras 모듈이 없습니다.', $script:AppName) | Out-Null
        return
    }
    $r = Import-GongramTextToTodos
    $lblStatus.Text = $r.Message
    if (-not $r.Ok) {
        [System.Windows.Forms.MessageBox]::Show($r.Message, $script:AppName) | Out-Null
    }
})

$btnTodoRelated.add_Click({
    if (-not (Get-Command Copy-RelatedDocumentNumber -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show('PenExtras 모듈이 없습니다.', $script:AppName) | Out-Null
        return
    }
    $raw = ''
    $a = Get-SelectedAlert
    if ($null -ne $a) { $raw = ("{0}`n{1}" -f $a.Title, $a.Body) }
    $r = Copy-RelatedDocumentNumber -RawText $raw
    $lblStatus.Text = $r.Message
    if ($r.Ok) {
        [System.Windows.Forms.MessageBox]::Show(('클립보드:`n{0}' -f $r.Line), $script:AppName) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show($r.Message, $script:AppName) | Out-Null
    }
})

# ---------- 폴링 ----------
$script:SeenMap = Get-SeenMap
$script:HighlightExpire = $null
$script:SeededSeen = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.add_Tick({
    try {
        $pids = @(Get-UcwareProcessIds)
        if (@($pids).Count -eq 0) {
            $lblStatus.Text = '메신저: 실행 중 아님 (ucware_m)'
        } else {
            $lblStatus.Text = ('메신저: 실행 중 (PID {0}) · {1}' -f ($pids -join ','), (Get-Date -Format 'HH:mm:ss'))
            $wins = @(Get-UcwareTopWindows)
            if (-not $script:SeededSeen) {
                foreach ($w in $wins) {
                    if (-not $script:SeenMap.ContainsKey($w.Key)) {
                        $script:SeenMap[$w.Key] = (Get-Date -Format 'o')
                    }
                }
                Save-SeenMap -Map $script:SeenMap
                $script:SeededSeen = $true
                $lblStatus.Text = ('메신저: 기준 창 {0}개 등록 · 이후 새 창만 알림' -f @($wins).Count)
                return
            }
            foreach ($w in $wins) {
                if ($script:SeenMap.ContainsKey($w.Key)) { continue }
                $script:SeenMap[$w.Key] = (Get-Date -Format 'o')
                $combined = "{0}`n{1}" -f $w.Title, $w.Body
                $cat = Get-CategoryFromText -Text $combined
                $item = Add-AlertItem -Title $w.Title -Body $w.Body -Category $cat
                if ($cat -and $script:KeywordToButton.ContainsKey($cat)) {
                    $btnName = $script:KeywordToButton[$cat]
                    Highlight-Button -BtnName $btnName
                    $script:HighlightExpire = (Get-Date).AddSeconds(30)
                }
                $tip = if ($cat) { '[{0}] {1}' -f $cat, $w.Title } else { $w.Title }
                if ($tip.Length -gt 80) { $tip = $tip.Substring(0, 80) + '…' }
                $notify.ShowBalloonTip(4000, 'PEN 알림 감지', $tip, 'Info')
                # 메신저→할 일 자동생성 제거 (하이라이트만)
            }
            if ($script:SeenMap.Count -gt 200) {
                $ordered = @($script:SeenMap.GetEnumerator() | Sort-Object { $_.Value } |
                    Select-Object -First ($script:SeenMap.Count - 150))
                foreach ($e in $ordered) { [void]$script:SeenMap.Remove($e.Key) }
            }
            Save-SeenMap -Map $script:SeenMap
        }
        if ($null -ne $script:HighlightExpire -and (Get-Date) -gt $script:HighlightExpire) {
            Highlight-Button -BtnName $null
            $script:HighlightExpire = $null
        }
        if (-not $script:KeepAliveTick) { $script:KeepAliveTick = 0 }
        $script:KeepAliveTick++
        if ($script:KeepAliveEnabled -and ($script:KeepAliveTick % 120) -eq 0) {
            if (Get-Command Invoke-PortalKeepAlive -ErrorAction SilentlyContinue) {
                $null = Invoke-PortalKeepAlive
            }
        }
        if (($script:KeepAliveTick % 6) -eq 0 -and $script:LblStatusChips -and (Get-Command Get-StatusChipText -ErrorAction SilentlyContinue)) {
            $script:LblStatusChips.Text = Get-StatusChipText
        }
    } catch {
        $lblStatus.Text = ('메신저 감시 오류: {0}' -f $_.Exception.Message)
    }
})

# ---------- 시작 ----------
Load-TodosIntoUi
Load-SchedulesIntoUi
Show-PenPage -Key 'home'
$timer.Start()
$form.add_Shown({
    Apply-AppleTheme -Root $form
    & $fitHome
    if (Get-Variable -Name NoticeFitChrome -Scope Script -ErrorAction SilentlyContinue) { if ($script:NoticeFitChrome) { & $script:NoticeFitChrome } }
    if (Get-Variable -Name TripFitChrome -Scope Script -ErrorAction SilentlyContinue) { if ($script:TripFitChrome) { & $script:TripFitChrome } }
    if ($script:LblStatusChips -and (Get-Command Get-StatusChipText -ErrorAction SilentlyContinue)) {
      $script:LblStatusChips.Text = Get-StatusChipText
    }
    $lblStatus.Text = '준비됨. 상신 안 함 · 메신저 5초 감시.'
    # capture helper
    try {
      $flag = Join-Path $PSScriptRoot 'cap\.select-page'
      if (Test-Path -LiteralPath $flag) {
        $pg = (Get-Content -LiteralPath $flag -Raw).Trim()
        if ($pg) { Show-PenPage -Key $pg }
      }
    } catch { }
})

Apply-AppleTheme -Root $form
[System.Windows.Forms.Application]::Run($form)

$timer.Stop()
$notify.Visible = $false
$notify.Dispose()
