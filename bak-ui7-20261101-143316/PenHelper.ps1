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
$script:UiBg       = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7')
$script:UiCard     = [System.Drawing.Color]::White
$script:UiAccent   = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
$script:UiText     = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
$script:UiMuted    = [System.Drawing.ColorTranslator]::FromHtml('#6E6E73')
$script:UiBorder   = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
$script:UiBtnSoft  = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
$script:UiFontUi   = New-Object System.Drawing.Font('맑은 고딕', 11)
$script:UiFontBtn  = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
$script:UiFontTitle= New-Object System.Drawing.Font('맑은 고딕', 13, [System.Drawing.FontStyle]::Bold)

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
  # calculator key default
  if ($AccentHex -eq '#E5E5EA' -or $AccentHex -eq '#F2F2F7') {
    $Button.BackColor = [System.Drawing.ColorTranslator]::FromHtml($AccentHex)
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 0
  } elseif ($AccentHex -and $outline) {
    $Button.BackColor = [System.Drawing.Color]::White
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = $script:UiBorder
  } elseif ($AccentHex -eq '#007AFF' -or $AccentHex -eq '#0071E3') {
    $Button.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderSize = 0
  } elseif ($AccentHex) {
    # category colors should not flood tiles — treat as soft key
    $Button.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 0
  } elseif ($Secondary) {
    $Button.BackColor = $script:UiBtnSoft
    $Button.ForeColor = $script:UiText
    $Button.FlatAppearance.BorderSize = 0
  } else {
    $Button.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderSize = 0
  }
  if ($isTile) {
    Set-RoundedRegion -Control $Button -Radius 12
    $Button.add_Resize({ Set-RoundedRegion -Control $this -Radius 12 })
  } elseif (-not $outline) {
    Set-RoundedRegion -Control $Button -Radius 8
    $Button.add_Resize({ Set-RoundedRegion -Control $this -Radius 8 })
  } else {
    $Button.Region = $null
  }
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
        $c.Padding = New-Object System.Windows.Forms.Padding(12)
      }
      elseif ($c -is [System.Windows.Forms.Panel] -or $c -is [System.Windows.Forms.FlowLayoutPanel]) {
        $tag = [string]$c.Tag
        if ($tag -eq 'bg') {
          $c.BackColor = $script:UiBg
        } elseif ($tag -eq 'card') {
          $c.BackColor = $script:UiCard
          # do NOT Set-RoundedRegion on cards — Region freezes early PreferredSize and clips width
          $c.Region = $null
        } elseif ($c.Dock -eq 'Fill' -or $c.Height -gt 48 -or $c.Width -gt 200) {
          $c.BackColor = $script:UiCard
        } else {
          $c.BackColor = $script:UiBg
        }
        # keep existing padding if already set (>=4); do not inflate beyond 12
        $c.Padding = New-Object System.Windows.Forms.Padding(
          [Math]::Min(12, [Math]::Max($c.Padding.Left, 8)),
          [Math]::Min(12, [Math]::Max($c.Padding.Top, 8)),
          [Math]::Min(12, [Math]::Max($c.Padding.Right, 8)),
          [Math]::Min(12, [Math]::Max($c.Padding.Bottom, 8))
        )
      }
      elseif ($c -is [System.Windows.Forms.Button]) {
        $hex = Get-UiColorFromTag -Control $c
        if ($hex -eq '#FF3B30') { $hex = '#E5E5EA' }
        if ($hex) {
          Set-AppleButton -Button $c -AccentHex $hex
        } else {
          $sec = ($c.Text -match '삭제|취소|◀|▶')
          Set-AppleButton -Button $c -Secondary:$sec
        }
      }
      elseif ($c -is [System.Windows.Forms.Label]) {
        if ([string]$c.Tag -eq 'section') {
          $c.ForeColor = $script:UiMuted
          $c.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
          $c.BackColor = [System.Drawing.Color]::Transparent
        } elseif ([string]$c.Tag -eq 'stephead') {
          $c.ForeColor = $script:UiText
          $c.Font = $script:UiFontTitle
          $c.BackColor = [System.Drawing.Color]::Transparent
        } elseif ([string]$c.Tag -eq 'statusbar') {
          $c.ForeColor = $script:UiText
          $c.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
        } else {
          $c.ForeColor = $script:UiText
          $c.Font = $script:UiFontUi
          $c.BackColor = [System.Drawing.Color]::Transparent
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
$pnlSidebar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
$pnlSidebar.Padding = New-Object System.Windows.Forms.Padding(8)

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "PEN`n도우미"
$lblBrand.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
$lblBrand.Font = New-Object System.Drawing.Font('맑은 고딕', 12, [System.Drawing.FontStyle]::Bold)
$lblBrand.AutoSize = $false
$lblBrand.Height = 56
$lblBrand.Dock = 'Top'
$lblBrand.TextAlign = 'MiddleLeft'
$lblBrand.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
$lblBrand.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')

$flowNav = New-Object System.Windows.Forms.FlowLayoutPanel
$flowNav.Dock = 'Fill'
$flowNav.FlowDirection = 'TopDown'
$flowNav.WrapContents = $false
$flowNav.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
$flowNav.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')

$script:NavButtons = @{}
$script:Pages = @{}
$script:CurrentPage = 'home'

function New-NavButton([string]$Key, [string]$Text) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $Text
  $b.Width = 148
  $b.Height = 40
  $b.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 0
  $b.Font = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
  $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
  $b.TextAlign = 'MiddleLeft'
  $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.Tag = $Key
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
  @{ K='todo'; T='▦  달력·할 일' },
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
$pnlStatusBar.Height = 30
$pnlStatusBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
$pnlStatusBar.ForeColor = $script:UiText
$pnlStatusBar.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
$pnlStatusBar.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
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
    try {
      if ($todoSplit -and $todoSplit.Width -gt 200) {
        $todoSplit.SplitterDistance = [Math]::Min(420, [Math]::Max(280, $todoSplit.Width - 340))
      }
    } catch { }
    Refresh-Calendar
  }
  foreach ($k in @($script:NavButtons.Keys)) {
    if ($k -eq $Key) {
      $script:NavButtons[$k].BackColor = [System.Drawing.Color]::White
      $script:NavButtons[$k].ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
      Set-RoundedRegion -Control $script:NavButtons[$k] -Radius 12
    } else {
      $script:NavButtons[$k].BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
      $script:NavButtons[$k].ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
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

[void]$form.Controls.Add($pnlContent)
[void]$form.Controls.Add($pnlStatusBar)
[void]$form.Controls.Add($pnlSidebar)

# --- HOME: calculator tiles for shortcuts + alerts ---
$homeScroll = New-Object System.Windows.Forms.Panel
$homeScroll.Dock = 'Fill'
$homeScroll.AutoScroll = $true
$homeScroll.BackColor = $script:UiBg
$homeScroll.Tag = 'bg'
$homeScroll.Padding = New-Object System.Windows.Forms.Padding(16)

$cardHomeTiles = New-Object System.Windows.Forms.Panel
$cardHomeTiles.AutoSize = $true
$cardHomeTiles.Padding = New-Object System.Windows.Forms.Padding(16)
$cardHomeTiles.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
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
$lblHomeHead.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
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
  '업무포털' = '업무포털을 엽니다'
}
$homeEmoji = @{
  '결재대기' = '●'
  '문서진행' = '■'
  '공람' = '◎'
  '발송대기' = '▲'
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
        Open-InChrome -Url $script:BtnUrlMap[$k]
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
$cardAlert.Padding = New-Object System.Windows.Forms.Padding(16)
$cardAlert.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
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

$script:HomeCards = @($cardHomeTiles, $cardAlert)
$script:HomeScroll = $homeScroll
# Dock Top = full content width
$cardAlert.Dock = 'Top'; $cardAlert.AutoSize = $false; $cardAlert.Height = 320
$cardHomeTiles.Dock = 'Top'; $cardHomeTiles.AutoSize = $false; $cardHomeTiles.Height = 160
[void]$homeScroll.Controls.Add($cardAlert)
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
    $script:HomeCards[1].Height = 320
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

# --- TODO + CAL combined ---
$todoSplit = New-Object System.Windows.Forms.SplitContainer
$todoSplit.Dock = 'Fill'
$todoSplit.Orientation = 'Vertical'
$todoSplit.SplitterDistance = 400
try { $todoSplit.Panel1MinSize = 280; $todoSplit.Panel2MinSize = 300 } catch { }
$todoSplit.BackColor = $script:UiBg

$pnlTodoTop = New-Object System.Windows.Forms.Panel
$pnlTodoTop.Dock = 'Top'
$pnlTodoTop.Height = 80
$pnlTodoTop.Padding = New-Object System.Windows.Forms.Padding(12)
$pnlTodoTop.BackColor = [System.Drawing.Color]::White
$pnlTodoTop.Tag = 'card'

$txtTodoTitle = New-Object System.Windows.Forms.TextBox
$txtTodoTitle.Location = New-Object System.Drawing.Point(12, 12)
$txtTodoTitle.Width = 220
$txtTodoTitle.Font = $script:UiFontUi

$dtDue = New-Object System.Windows.Forms.DateTimePicker
$dtDue.Location = New-Object System.Drawing.Point(240, 12)
$dtDue.Width = 120
$dtDue.Format = 'Short'
$dtDue.ShowCheckBox = $true
$dtDue.Checked = $false

$btnTodoAdd = New-Object System.Windows.Forms.Button
$btnTodoAdd.Text = '추가'
$btnTodoAdd.Location = New-Object System.Drawing.Point(370, 10)
$btnTodoAdd.Size = New-Object System.Drawing.Size(80, 36)
$btnTodoAdd.FlatStyle = 'Flat'
$btnTodoAdd.Tag = 'uicolor:#007AFF'
$btnTodoAdd.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
$btnTodoAdd.ForeColor = [System.Drawing.Color]::White
$btnTodoAdd.FlatAppearance.BorderSize = 0

$lblTodoHint = New-Object System.Windows.Forms.Label
$lblTodoHint.Text = '할 일 / 마감(선택)'
$lblTodoHint.Location = New-Object System.Drawing.Point(12, 48)
$lblTodoHint.AutoSize = $true

[void]$pnlTodoTop.Controls.Add($txtTodoTitle)
[void]$pnlTodoTop.Controls.Add($dtDue)
[void]$pnlTodoTop.Controls.Add($btnTodoAdd)
[void]$pnlTodoTop.Controls.Add($lblTodoHint)

$lstTodos = New-Object System.Windows.Forms.CheckedListBox
$lstTodos.Dock = 'Fill'
$lstTodos.IntegralHeight = $false
$lstTodos.CheckOnClick = $true
$lstTodos.Font = $script:UiFontUi

$pnlTodoBot = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlTodoBot.Dock = 'Bottom'
$pnlTodoBot.Height = 52
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

$btnTodoToSched = New-Object System.Windows.Forms.Button
$btnTodoToSched.Text = '일정으로 등록'
$btnTodoToSched.Size = New-Object System.Drawing.Size(130, 36)
$btnTodoToSched.FlatStyle = 'Flat'
$btnTodoToSched.Tag = 'uicolor:#E5E5EA;tile'

[void]$pnlTodoBot.Controls.Add($btnTodoDel)
[void]$pnlTodoBot.Controls.Add($btnTodoToSched)
[void]$pnlTodoBot.Controls.Add($btnTodoOpen)

$todoSplit.Panel1.Controls.Add($lstTodos)
$todoSplit.Panel1.Controls.Add($pnlTodoBot)
$todoSplit.Panel1.Controls.Add($pnlTodoTop)

$pnlCalTop = New-Object System.Windows.Forms.Panel
$pnlCalTop.Dock = 'Top'
$pnlCalTop.Height = 48
$pnlCalTop.BackColor = [System.Drawing.Color]::White
$pnlCalTop.Tag = 'card'
$pnlCalTop.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

$lblCalMonth = New-Object System.Windows.Forms.Label
$lblCalMonth.Text = '일정 (가까운 마감 순)'
$lblCalMonth.Dock = 'Fill'
$lblCalMonth.Font = $script:UiFontTitle
$lblCalMonth.ForeColor = $script:UiText
$lblCalMonth.TextAlign = 'MiddleLeft'
$lblCalMonth.Tag = 'stephead'
[void]$pnlCalTop.Controls.Add($lblCalMonth)

$scrollSched = New-Object System.Windows.Forms.Panel
$scrollSched.Dock = 'Fill'
$scrollSched.AutoScroll = $true
$scrollSched.BackColor = $script:UiBg
$scrollSched.Padding = New-Object System.Windows.Forms.Padding(8)
$scrollSched.Tag = 'bg'

$flowSched = New-Object System.Windows.Forms.FlowLayoutPanel
$flowSched.Dock = 'Top'
$flowSched.AutoSize = $true
$flowSched.FlowDirection = 'TopDown'
$flowSched.WrapContents = $false
$flowSched.BackColor = $script:UiBg
$flowSched.Tag = 'bg'
$flowSched.Padding = New-Object System.Windows.Forms.Padding(4)
[void]$scrollSched.Controls.Add($flowSched)

$todoSplit.Panel2.Controls.Add($scrollSched)
$todoSplit.Panel2.Controls.Add($pnlCalTop)
[void]$pageTodo.Controls.Add($todoSplit)
$script:FlowSched = $flowSched
$script:ScrollSched = $scrollSched

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
        }
    }
    Save-Todos -Todos $arr
}

function Refresh-TodoList {
    $script:SuppressTodoCheck = $true
    $lstTodos.BeginUpdate()
    try {
        $lstTodos.Items.Clear()
        foreach ($t in $script:TodoList) {
            $due = if ($t.Due) { ' · {0}' -f $t.Due } else { '' }
            $done = if ($t.Done) { '[완료] ' } else { '' }
            $display = '{0}{1}{2}' -f $done, $t.Title, $due
            $idx = $lstTodos.Items.Add($display)
            if ($t.Done) { $lstTodos.SetItemChecked($idx, $true) }
        }
    } finally {
        $lstTodos.EndUpdate()
        $script:SuppressTodoCheck = $false
    }
    Refresh-Calendar
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
    }
    $script:TodoList.Insert(0, $item)
    Persist-Todos
    Refresh-TodoList
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
        })
    }
    Refresh-TodoList
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
        })
    }
    Refresh-Calendar
}

function Add-ScheduleItem {
    param([string]$Title, [string]$Body = '', [string]$Date = '', [string]$Source = 'manual')
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
    }
    $script:ScheduleList.Insert(0, $item)
    Persist-Schedules
    Refresh-Calendar
    return $item
}

function Refresh-Calendar {
    if ($null -eq $script:FlowSched) { return }
    $flow = $script:FlowSched
    $flow.SuspendLayout()
    $flow.Controls.Clear()
    try {
        $sorted = @($script:ScheduleList | Sort-Object {
            if ($_.Date) { $_.Date } else { '9999-12-31' }
        }, Title)
        if (@($sorted).Count -eq 0) {
            $empty = New-Object System.Windows.Forms.Label
            $empty.Text = '일정이 없습니다. 할 일에서 [일정으로 등록]을 누르세요.'
            $empty.AutoSize = $true
            $empty.ForeColor = $script:UiMuted
            $empty.Margin = New-Object System.Windows.Forms.Padding(8)
            [void]$flow.Controls.Add($empty)
            return
        }
        $hostW = 360
        try {
            if ($script:ScrollSched -and $script:ScrollSched.ClientSize.Width -gt 80) {
                $hostW = [Math]::Max(280, $script:ScrollSched.ClientSize.Width - 24)
            }
        } catch { }
        foreach ($s in $sorted) {
            $innerW = [Math]::Max(200, $hostW - 20)
            $row = New-Object System.Windows.Forms.Panel
            $row.Width = $hostW
            $row.Height = 108
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

            $lblDate = New-Object System.Windows.Forms.Label
            $lblDate.Text = $(if ($s.Date) { $s.Date } else { '(날짜없음)' })
            $lblDate.Location = New-Object System.Drawing.Point(10, 6)
            $lblDate.AutoSize = $true
            $lblDate.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
            $lblDate.ForeColor = $script:UiMuted

            $lblTitle = New-Object System.Windows.Forms.Label
            $lblTitle.Text = $s.Title
            $lblTitle.Location = New-Object System.Drawing.Point(10, 26)
            $lblTitle.Size = New-Object System.Drawing.Size($innerW, 24)
            $lblTitle.Font = $script:UiFontUi
            $lblTitle.ForeColor = $script:UiText

            $btnG = New-Object System.Windows.Forms.Button
            $btnG.Size = New-Object System.Drawing.Size([Math]::Min(200, $innerW), 32)
            $btnG.Location = New-Object System.Drawing.Point(10, 56)
            $btnG.FlatStyle = 'Flat'
            $btnG.Font = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
            $btnG.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnG.Tag = $s.Id
            $alreadySaved = [bool]$s.GoogleSaved
            if (-not $alreadySaved -and (Get-Command Test-GCalItemSaved -ErrorAction SilentlyContinue)) {
                if (Test-GCalItemSaved -ItemId $s.Id) { $alreadySaved = $true }
            }
            if ($alreadySaved) {
                $s.GoogleSaved = $true
                $btnG.Text = '구글 캘린더에 저장됨'
                $btnG.Width = [Math]::Min(200, $innerW)
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
                    $id = [string]$sender.Tag
                    $item = $null
                    foreach ($x in @($script:ScheduleList)) { if ($x.Id -eq $id) { $item = $x; break } }
                    if ($null -eq $item) { return }
                    $sender.Enabled = $false
                    $sender.Text = '저장 중…'
                    try {
                        if (-not (Get-Command Save-ScheduleToGoogleCalendar -ErrorAction SilentlyContinue)) {
                            [System.Windows.Forms.MessageBox]::Show('PenGoogleCal 모듈이 없습니다.', $script:AppName) | Out-Null
                            $sender.Text = '구글 캘린더'; $sender.Enabled = $true
                            return
                        }
                        $r = Save-ScheduleToGoogleCalendar -ItemId $item.Id -Title $item.Title -DateYmd $item.Date -Body $item.Body
                        if ($r.Ok) {
                            $item.GoogleSaved = $true
                            Persist-Schedules
                            $sender.Text = '구글 캘린더에 저장됨'
                            $sender.Width = 150
                            $sender.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
                            $sender.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#34C759')
                            $sender.Enabled = $false
                            $lblStatus.Text = ('일정 저장 확인: {0} · {1}' -f $item.Date, $item.Title)
                        } else {
                            $sender.Text = '구글 캘린더'
                            $sender.Enabled = $true
                            $msg = if ($r.Message) { [string]$r.Message } else { '저장 실패' }
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
$settingsScroll.Padding = New-Object System.Windows.Forms.Padding(16)
$settingsCard = New-Object System.Windows.Forms.Panel
$settingsCard.AutoSize = $true
$settingsCard.Padding = New-Object System.Windows.Forms.Padding(16)
$settingsCard.BackColor = [System.Drawing.Color]::White
$settingsCard.Tag = 'card'
$settingsInner = New-Object System.Windows.Forms.FlowLayoutPanel
$settingsInner.FlowDirection = 'TopDown'
$settingsInner.AutoSize = $true
$settingsInner.WrapContents = $false
$settingsInner.BackColor = [System.Drawing.Color]::White
$settingsInner.Tag = 'card'
$lblSet = New-Object System.Windows.Forms.Label
$lblSet.Text = '설정'
$lblSet.Font = $script:UiFontTitle
$lblSet.AutoSize = $true
$lblSet.Tag = 'stephead'
$lblSetInfo = New-Object System.Windows.Forms.Label
$lblSetInfo.AutoSize = $true
$lblSetInfo.MaximumSize = New-Object System.Drawing.Size(560, 0)
$lblSetInfo.Font = $script:UiFontUi
$lblSetInfo.Text = "데이터: $script:DataDir`n초안: $script:DraftDir`n메신저→할 일/공문 자동생성은 사용하지 않습니다.`n알림은 하이라이트만 합니다.`n일정 [구글 캘린더]: Chrome 템플릿 URL → 저장 클릭(로그인된 Chrome).`n결재올림/발송/상신은 절대 클릭하지 않습니다."
[void]$settingsInner.Controls.Add($lblSet)
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

$lstTodos.add_ItemCheck({
    param($sender, $e)
    if ($script:SuppressTodoCheck) { return }
    $idx = $e.Index
    if ($idx -lt 0 -or $idx -ge @($script:TodoList).Count) { return }
    $script:TodoList[$idx].Done = ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
    Persist-Todos
    $form.BeginInvoke([action]{ Refresh-TodoList }) | Out-Null
})

$btnTodoDel.add_Click({
    $idx = $lstTodos.SelectedIndex
    if ($idx -lt 0) {
        [System.Windows.Forms.MessageBox]::Show('삭제할 항목을 선택하세요.', $script:AppName) | Out-Null
        return
    }
    $script:TodoList.RemoveAt($idx)
    Persist-Todos
    Refresh-TodoList
})

$btnTodoOpen.add_Click({ Open-InChrome -Url $script:Urls['업무포털'] })

$btnTodoToSched.add_Click({
    $idx = $lstTodos.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($script:TodoList).Count) {
        [System.Windows.Forms.MessageBox]::Show('할 일을 선택하세요.', $script:AppName) | Out-Null
        return
    }
    $titem = $script:TodoList[$idx]
    $due = if ($titem.Due) { [string]$titem.Due } else { (Get-Date).ToString('yyyy-MM-dd') }
    Add-ScheduleItem -Title $titem.Title -Body $titem.Body -Date $due -Source 'todo'
    $lblStatus.Text = ('일정 등록: {0} · {1}' -f $due, $titem.Title)
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
    $lblStatus.Text = '준비됨. 메신저 창을 5초마다 확인합니다.'
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
