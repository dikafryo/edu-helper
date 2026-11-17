# PenExtras.ps1 — tools-review 상위 5기능 (채우기만, 상신/저장/결재 금지)
# Dot-sourced by PenHelper after JSON helpers.

Set-StrictMode -Version Latest

$script:ExtrasBadgePath = Join-Path $script:DataDir 'portal_badges.json'
$script:ExtrasKeepAlivePath = Join-Path $script:DataDir 'keepalive.json'
$script:DutyPresetsPath = Join-Path $script:DataDir 'duty_presets.json'
$script:PortalKeepAliveUrl = 'https://klef.pen.go.kr/portal/main.do'
$script:TravelSettleUrl = 'https://neis.me/v1/etc/travel/'
$script:BadgeCounts = @{ '결재대기' = 0; '공람' = 0; '발송대기' = 0 }
$script:KeepAliveEnabled = $true
$script:LastKeepAlive = $null
$script:StatusChips = [ordered]@{
  Safety = '상신 안 함'
  Session = '세션: —'
  Draft = '기안창: —'
  Keep = '유지: ON'
}

function Get-DefaultDutyPresets {
  return @(
    [pscustomobject]@{ Key='시간외'; Label='시간외'; Reason='시간외근무'; Time='18:00~20:00'; Url='https://pen.eduptl.kr/bpm_man_mn00_001.do' },
    [pscustomobject]@{ Key='연가'; Label='연가'; Reason='연가'; Time='종일'; Url='https://pen.eduptl.kr/bpm_man_mn00_001.do' },
    [pscustomobject]@{ Key='조퇴'; Label='조퇴'; Reason='조퇴'; Time='16:00'; Url='https://pen.eduptl.kr/bpm_man_mn00_001.do' },
    [pscustomobject]@{ Key='외출'; Label='외출'; Reason='외출'; Time='14:00~15:00'; Url='https://pen.eduptl.kr/bpm_man_mn00_001.do' }
  )
}

function Get-DutyPresets {
  $data = Read-JsonFile -Path $script:DutyPresetsPath -Default $null
  if ($null -eq $data) {
    $d = Get-DefaultDutyPresets
    Write-JsonFile -Path $script:DutyPresetsPath -Object @($d)
    return @($d)
  }
  if ($data -isnot [System.Array]) { return @($data) }
  return @($data)
}

# ----- 1) 관련문서번호 복사 -----
function Format-RelatedDocLine {
  param(
    [string]$Org = '',
    [string]$Number = '',
    [string]$DateYmd = '',
    [string]$Title = ''
  )
  $org = if ($Org) { $Org.Trim() } else { '기관' }
  $num = if ($Number) { $Number.Trim() } else { '' }
  $dt = ''
  if ($DateYmd -match '(\d{4})-(\d{2})-(\d{2})') {
    $dt = '{0}.{1}.{2}' -f $Matches[1], $Matches[2], $Matches[3]
  } elseif ($DateYmd) { $dt = $DateYmd.Trim() }
  else { $dt = (Get-Date -Format 'yyyy.MM.dd') }
  $title = if ($Title) { $Title.Trim() -replace '\s+', ' ' } else { '' }
  if ($title.Length -gt 80) { $title = $title.Substring(0, 80) + '…' }
  if ($num) {
    return ("{0}-{1}({2}) '{3}'" -f $org, $num, $dt, $title)
  }
  return ("{0}({1}) '{2}'" -f $org, $dt, $title)
}

function Parse-RelatedDocFromText {
  param([string]$Text)
  $org = ''; $num = ''; $date = ''; $title = ''
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [pscustomobject]@{ Org=$org; Number=$num; DateYmd=$date; Title=$title }
  }
  $t = $Text.Trim()
  # e.g. 부산광역시교육청-1234(2026.11.01) or 문서번호 1234
  if ($t -match '([가-힣A-Za-z0-9]+(?:교육청|학교|지원청)?)\s*[-–]?\s*(\d{2,6})') {
    $org = $Matches[1]; $num = $Matches[2]
  } elseif ($t -match '문서\s*번호\s*[:：]?\s*(\d{2,8})') {
    $num = $Matches[1]
  } elseif ($t -match '(?<![0-9])(\d{3,6})(?![0-9])') {
    $num = $Matches[1]
  }
  $due = Get-DueDateFromText -Text $t
  if ($due) { $date = $due }
  elseif ($t -match '(\d{4})[.\-/년]\s*(\d{1,2})[.\-/월]\s*(\d{1,2})') {
    $date = '{0:D4}-{1:D2}-{2:D2}' -f [int]$Matches[1],[int]$Matches[2],[int]$Matches[3]
  }
  if ($t -match "[""'「]([^""'」]{3,80})[""'」]") { $title = $Matches[1] }
  elseif ($t -match '제\s*목\s*[:：]\s*(.+)$') { $title = $Matches[1].Trim() }
  else {
    $line = ($t -split "`n")[0].Trim()
    if ($line.Length -gt 8) { $title = $line }
  }
  if (-not $org) { $org = '부산광역시교육청' }
  return [pscustomobject]@{ Org=$org; Number=$num; DateYmd=$date; Title=$title }
}

function Copy-RelatedDocumentNumber {
  param([string]$RawText = '')
  if ([string]::IsNullOrWhiteSpace($RawText)) {
    try { $RawText = [System.Windows.Forms.Clipboard]::GetText() } catch { $RawText = '' }
  }
  if ([string]::IsNullOrWhiteSpace($RawText)) {
    return [pscustomobject]@{ Ok=$false; Message='복사할 원문이 없습니다. 문서 제목·번호를 클립보드에 복사하거나 입력하세요.' }
  }
  $p = Parse-RelatedDocFromText -Text $RawText
  $line = Format-RelatedDocLine -Org $p.Org -Number $p.Number -DateYmd $p.DateYmd -Title $p.Title
  try {
    [System.Windows.Forms.Clipboard]::SetText($line)
  } catch {
    return [pscustomobject]@{ Ok=$false; Message=('클립보드 실패: ' + $_.Exception.Message) }
  }
  return [pscustomobject]@{ Ok=$true; Line=$line; Message='관련문서 형식으로 복사됨 (상신 안 함)' }
}

# ----- 2) 세션 keep-alive + 배지 -----
function Save-BadgeCounts {
  Write-JsonFile -Path $script:ExtrasBadgePath -Object $script:BadgeCounts
}

function Load-BadgeCounts {
  $d = Read-JsonFile -Path $script:ExtrasBadgePath -Default $null
  if ($null -eq $d) { return }
  foreach ($k in @('결재대기','공람','발송대기')) {
    if ($d.PSObject.Properties.Name -contains $k) {
      try { $script:BadgeCounts[$k] = [int]$d.$k } catch { }
    }
  }
}

function Invoke-PortalKeepAlive {
  if (-not $script:KeepAliveEnabled) {
    return [pscustomobject]@{ Ok=$false; Message='세션유지 OFF' }
  }
  # Open portal main in existing Chrome profile (no credentials stored). Never clicks 상신.
  try {
    if (Get-Command Open-InChrome -ErrorAction SilentlyContinue) {
      Open-InChrome -Url $script:PortalKeepAliveUrl
    } else {
      Start-Process $script:PortalKeepAliveUrl | Out-Null
    }
    $script:LastKeepAlive = Get-Date
    $script:StatusChips['Session'] = '세션: 유지시도 ' + (Get-Date -Format 'HH:mm')
    $script:StatusChips['Keep'] = '유지: ON'
    Write-JsonFile -Path $script:ExtrasKeepAlivePath -Object ([pscustomobject]@{
      Last = (Get-Date -Format 'o'); Url = $script:PortalKeepAliveUrl
    })
    return [pscustomobject]@{ Ok=$true; Message='세션 유지 URL 열림 (로그인·상신은 사용자)' }
  } catch {
    return [pscustomobject]@{ Ok=$false; Message=$_.Exception.Message }
  }
}

function Update-PortalBadgesFromText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $changed = $false
  if ($Text -match '결재\s*대기[^\d]{0,6}(\d{1,3})' -or $Text -match '미결\s*(\d{1,3})') {
    $script:BadgeCounts['결재대기'] = [int]$Matches[1]; $changed = $true
  }
  if ($Text -match '공람[^\d]{0,8}(\d{1,3})') {
    $script:BadgeCounts['공람'] = [int]$Matches[1]; $changed = $true
  }
  if ($Text -match '발송\s*대기[^\d]{0,6}(\d{1,3})') {
    $script:BadgeCounts['발송대기'] = [int]$Matches[1]; $changed = $true
  }
  if ($changed) { Save-BadgeCounts }
  return $changed
}

function Refresh-PortalBadgesFromChrome {
  # Best-effort: read top-level Chrome window names / a few text nodes for counts.
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  $found = $false
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Window)
    $col = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    for ($i = 0; $i -lt $col.Count; $i++) {
      $w = $col.Item($i)
      $n = ''
      try { $n = [string]$w.Current.Name } catch { continue }
      if ($n -notmatch 'Chrome|에듀파인|K-에듀|업무포털|klef') { continue }
      if (Update-PortalBadgesFromText -Text $n) { $found = $true }
      try {
        $tcond = New-Object System.Windows.Automation.PropertyCondition(
          [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
          [System.Windows.Automation.ControlType]::Text)
        $texts = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tcond)
        $limit = [Math]::Min(80, $texts.Count)
        for ($j = 0; $j -lt $limit; $j++) {
          $tn = ''
          try { $tn = [string]$texts.Item($j).Current.Name } catch { continue }
          if ($tn -and (Update-PortalBadgesFromText -Text $tn)) { $found = $true }
        }
      } catch { }
    }
  } catch { }
  return [pscustomobject]@{ Ok=$true; Found=$found; Counts=$script:BadgeCounts }
}

function Update-DraftWindowChip {
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Window)
    $col = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    $hit = $false
    for ($i = 0; $i -lt $col.Count; $i++) {
      $n = ''
      try { $n = [string]$col.Item($i).Current.Name } catch { continue }
      if ($n -match '기안|한글|HWP|공문') { $hit = $true; break }
    }
    $script:StatusChips['Draft'] = if ($hit) { '기안창: 감지' } else { '기안창: 없음' }
  } catch {
    $script:StatusChips['Draft'] = '기안창: —'
  }
}

# ----- 3) 공람 → 할 일/기한 -----
function Extract-GongramActionItems {
  param([string]$Text)
  $items = New-Object System.Collections.ArrayList
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $lines = $Text -split "(`r`n|`n|`r)"
  $buf = New-Object System.Collections.ArrayList
  foreach ($ln in $lines) {
    $s = $ln.Trim()
    if (-not $s) { continue }
    $isAction = $false
    if ($s -match '까지|기한|제출|신청|회신|보고|조치|시행|마감|요망|바랍니다') { $isAction = $true }
    if ($s -match '^\s*[\d①②③④⑤⑥⑦⑧⑨⑩\-•*]+\s*') { $isAction = $true }
    $due = Get-DueDateFromText -Text $s
    if ($due) { $isAction = $true }
    if ($isAction) {
      $title = $s
      if ($title.Length -gt 90) { $title = $title.Substring(0, 90) + '…' }
      [void]$items.Add([pscustomobject]@{
        Title = $title
        Due = $due
        Body = $s
        Source = '공람'
      })
    }
  }
  if (@($items).Count -eq 0) {
    # fallback: whole first line + any due
    $due = Get-DueDateFromText -Text $Text
    $title = (($Text -split "`n")[0]).Trim()
    if ($title.Length -gt 90) { $title = $title.Substring(0, 90) + '…' }
    if ($title) {
      [void]$items.Add([pscustomobject]@{ Title=$title; Due=$due; Body=$Text; Source='공람' })
    }
  }
  return @($items)
}

function Import-GongramTextToTodos {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) {
    try { $Text = [System.Windows.Forms.Clipboard]::GetText() } catch { $Text = '' }
  }
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [pscustomobject]@{ Ok=$false; Count=0; Message='공람 원문/클립보드가 비었습니다.' }
  }
  $extracted = @(Extract-GongramActionItems -Text $Text)
  $n = 0
  foreach ($it in $extracted) {
    if (Get-Command Add-TodoItem -ErrorAction SilentlyContinue) {
      Add-TodoItem -Title $it.Title -Body $it.Body -Due $it.Due -Source '공람'
      $n++
    }
  }
  return [pscustomobject]@{ Ok=($n -gt 0); Count=$n; Message=('{0}건 할 일로 추가 (상신 안 함)' -f $n) }
}

# ----- 4) 복무 프리셋 (채우기만) -----
function Invoke-DutyPresetFill {
  param([string]$Key)
  $preset = $null
  foreach ($p in @(Get-DutyPresets)) {
    if ([string]$p.Key -eq $Key -or [string]$p.Label -eq $Key) { $preset = $p; break }
  }
  if ($null -eq $preset) {
    return [pscustomobject]@{ Ok=$false; Message='프리셋 없음' }
  }
  $hint = @(
    '【복무 프리셋 — 채우기만 / 상신 안 함】',
    ('유형: {0}' -f $preset.Label),
    ('사유: {0}' -f $preset.Reason),
    ('시간: {0}' -f $preset.Time),
    ('날짜: {0}' -f (Get-Date -Format 'yyyy-MM-dd')),
    '',
    '포털 복무 화면에서 위 값을 붙여넣거나 확인 후 직접 상신하세요.'
  ) -join "`r`n"
  try { [System.Windows.Forms.Clipboard]::SetText($hint) } catch { }
  $url = [string]$preset.Url
  if (-not $url) { $url = $script:Urls['업무포털'] }
  if (Get-Command Open-InChrome -ErrorAction SilentlyContinue) {
    Open-InChrome -Url $url
  } else {
    Start-Process $url | Out-Null
  }
  # Soft fill attempt via shared trip filler shape if available
  if (Get-Command Invoke-TripFormFill -ErrorAction SilentlyContinue) {
    $draft = [pscustomobject]@{
      Reason = [string]$preset.Reason
      Region = '관내'
      Date = (Get-Date -Format 'yyyy-MM-dd')
      Time = [string]$preset.Time
      Place = ''
    }
    try {
      $null = Invoke-TripFormFill -Draft $draft
    } catch { }
  }
  return [pscustomobject]@{
    Ok=$true
    Message=('{0} 프리셋 값 복사·포털 열림 (상신/저장 안 함)' -f $preset.Label)
    Hint=$hint
  }
}

# ----- 5) 여비정산 이어가기 (외부 열기+힌트, 제출 없음) -----
function Start-TravelSettlementContinuation {
  param(
    [string]$Place = '',
    [string]$Date = '',
    [string]$Reason = '',
    [string]$Region = '관외'
  )
  if (-not $Date) { $Date = (Get-Date -Format 'yyyy-MM-dd') }
  if (-not $Place) {
    try {
      if ($script:TxtTripPlace -and $script:TxtTripPlace.Text) { $Place = [string]$script:TxtTripPlace.Text }
    } catch { }
  }
  if (-not $Reason) {
    try {
      if ($script:TxtTripReason -and $script:TxtTripReason.Text) { $Reason = [string]$script:TxtTripReason.Text }
    } catch { }
  }
  $hint = @(
    '【여비정산 이어가기 — 제출/상신 안 함】',
    ('구분: {0}' -f $Region),
    ('날짜: {0}' -f $Date),
    ('장소: {0}' -f $Place),
    ('사유: {0}' -f $Reason),
    '',
    'neis.me 여비정산 페이지를 열었습니다. 위 값을 참고해 직접 입력하세요.'
  ) -join "`r`n"
  try { [System.Windows.Forms.Clipboard]::SetText($hint) } catch { }
  if (Get-Command Open-InChrome -ErrorAction SilentlyContinue) {
    Open-InChrome -Url $script:TravelSettleUrl
  } else {
    Start-Process $script:TravelSettleUrl | Out-Null
  }
  return [pscustomobject]@{ Ok=$true; Message='여비정산 페이지 열림 + 힌트 복사 (제출 안 함)'; Hint=$hint }
}

function Get-StatusChipText {
  Update-DraftWindowChip
  $parts = @()
  foreach ($k in @($script:StatusChips.Keys)) { $parts += [string]$script:StatusChips[$k] }
  return ($parts -join '  ·  ')
}

Load-BadgeCounts

# ----- 6) 공문접수 → 과제카드 자동추천 (로컬만, 저장/접수/확인 미클릭) -----
$script:TaskCardsPath = Join-Path $script:DataDir 'task_cards.json'
$script:TaskCardRulesPath = Join-Path $script:DataDir 'task_card_rules.json'
$script:GongmunRecvUrl = 'https://klef.pen.go.kr/portal/link.do?link=recvWait'

function Get-DefaultTaskCards {
  return @(
    [pscustomobject]@{ Id='tc_edu'; Name='교육과정운영'; Keywords=@('교육과정','수업','평가','성취기준','교과') },
    [pscustomobject]@{ Id='tc_life'; Name='생활지도'; Keywords=@('생활','학생지도','선도','교칙','봉사') },
    [pscustomobject]@{ Id='tc_safe'; Name='안전·재난'; Keywords=@('안전','재난','소방','훈련','응급','감염') },
    [pscustomobject]@{ Id='tc_hr'; Name='인사·복무'; Keywords=@('인사','복무','연가','출장','시간외','발령') },
    [pscustomobject]@{ Id='tc_acct'; Name='예산·회계'; Keywords=@('예산','회계','품의','지출','계약','세입') },
    [pscustomobject]@{ Id='tc_fac'; Name='시설·환경'; Keywords=@('시설','공사','환경','석면','석면','석면철거','냉난방') },
    [pscustomobject]@{ Id='tc_info'; Name='정보·보안'; Keywords=@('정보','보안','개인정보','시스템','네트워크','홈페이지') },
    [pscustomobject]@{ Id='tc_event'; Name='행사·연수'; Keywords=@('연수','행사','워크숍','세미나','대회','체험') },
    [pscustomobject]@{ Id='tc_etc'; Name='일반행정'; Keywords=@('공문','협조','통보','안내','제출','보고') }
  )
}

function Get-TaskCards {
  $data = Read-JsonFile -Path $script:TaskCardsPath -Default $null
  if ($null -eq $data) {
    $d = Get-DefaultTaskCards
    Write-JsonFile -Path $script:TaskCardsPath -Object @($d)
    return @($d)
  }
  if ($data -isnot [System.Array]) { return @($data) }
  return @($data)
}

function Save-TaskCards {
  param($Cards)
  Write-JsonFile -Path $script:TaskCardsPath -Object @($Cards)
}

function Get-TaskCardRules {
  $data = Read-JsonFile -Path $script:TaskCardRulesPath -Default $null
  if ($null -eq $data) {
    $d = [pscustomobject]@{
      Rules = @()
      History = @()
      Updated = (Get-Date -Format 'o')
    }
    Write-JsonFile -Path $script:TaskCardRulesPath -Object $d
    return $d
  }
  if (-not $data.Rules) { try { $data | Add-Member -NotePropertyName Rules -NotePropertyValue @() -Force } catch { } }
  if (-not $data.History) { try { $data | Add-Member -NotePropertyName History -NotePropertyValue @() -Force } catch { } }
  return $data
}

function Save-TaskCardRules {
  param($Obj)
  $Obj.Updated = (Get-Date -Format 'o')
  Write-JsonFile -Path $script:TaskCardRulesPath -Object $Obj
}

function Get-TextTokens {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $t = $Text.ToLowerInvariant()
  $t = $t -replace '[^\p{L}\p{N}\s]', ' '
  $parts = @($t -split '\s+' | Where-Object { $_ -and $_.Length -ge 2 })
  return @($parts | Select-Object -Unique)
}

function Match-TaskCards {
  param(
    [string]$Title = '',
    [string]$Body = '',
    [int]$Top = 3
  )
  $text = ('{0} {1}' -f $Title, $Body).Trim()
  $tokens = @(Get-TextTokens -Text $text)
  $cards = @(Get-TaskCards)
  $rules = Get-TaskCardRules
  $ruleList = @()
  try { $ruleList = @($rules.Rules) } catch { $ruleList = @() }
  $hist = @()
  try { $hist = @($rules.History) } catch { $hist = @() }

  $scores = New-Object System.Collections.Generic.List[object]
  foreach ($c in $cards) {
    $name = [string]$c.Name
    if (-not $name) { continue }
    $score = 0.0
    $hits = New-Object System.Collections.Generic.List[string]
    # name contained in text
    if ($text -and $name -and ($text -like ('*{0}*' -f $name))) {
      $score += 40
      [void]$hits.Add(('이름:{0}' -f $name))
    }
    $kws = @()
    try { $kws = @($c.Keywords) } catch { $kws = @() }
    foreach ($kw in $kws) {
      $k = [string]$kw
      if (-not $k) { continue }
      if ($text -like ('*{0}*' -f $k)) {
        $score += 18
        [void]$hits.Add($k)
      } elseif ($tokens -contains $k.ToLowerInvariant()) {
        $score += 12
        [void]$hits.Add($k)
      }
    }
    # editable rules: keyword -> card Id/Name
    foreach ($r in $ruleList) {
      $rk = [string]$r.Keyword
      $rid = [string]$r.CardId
      $rn = [string]$r.CardName
      if (-not $rk) { continue }
      $matchCard = ($rid -and $rid -eq [string]$c.Id) -or ($rn -and $rn -eq $name)
      if (-not $matchCard) { continue }
      if ($text -like ('*{0}*' -f $rk)) {
        $w = 25
        try { if ($r.Weight) { $w = [double]$r.Weight } } catch { }
        $score += $w
        [void]$hits.Add(('규칙:{0}' -f $rk))
      }
    }
    # learn from past picks
    $pickBoost = 0
    foreach ($h in $hist) {
      $hn = [string]$h.CardName
      $hid = [string]$h.CardId
      if (($hid -and $hid -eq [string]$c.Id) -or ($hn -eq $name)) {
        $pickBoost += 3
        $hk = [string]$h.KeywordHint
        if ($hk -and ($text -like ('*{0}*' -f $hk))) { $pickBoost += 8 }
      }
    }
    if ($pickBoost -gt 30) { $pickBoost = 30 }
    $score += $pickBoost
    if ($score -le 0 -and $kws.Count -eq 0) { continue }
    [void]$scores.Add([pscustomobject]@{
      Id = [string]$c.Id
      Name = $name
      Score = [Math]::Round($score, 1)
      Hits = (@($hits) -join ', ')
      Card = $c
    })
  }
  if ($scores.Count -eq 0) {
    # fallback: return first cards with tiny scores so UI still shows choices
    $i = 0
    foreach ($c in ($cards | Select-Object -First $Top)) {
      $i++
      [void]$scores.Add([pscustomobject]@{
        Id=[string]$c.Id; Name=[string]$c.Name; Score=[Math]::Round(1.0 * ($Top - $i + 1), 1); Hits='기본'; Card=$c
      })
    }
  }
  $ranked = @($scores | Sort-Object Score -Descending | Select-Object -First $Top)
  return $ranked
}

function Record-TaskCardPick {
  param(
    [string]$CardId,
    [string]$CardName,
    [string]$Title = '',
    [string]$Body = ''
  )
  $rules = Get-TaskCardRules
  $hist = New-Object System.Collections.Generic.List[object]
  try { foreach ($h in @($rules.History)) { [void]$hist.Add($h) } } catch { }
  $tokens = @(Get-TextTokens -Text ('{0} {1}' -f $Title, $Body))
  $hint = ''
  if ($tokens.Count -gt 0) { $hint = [string]$tokens[0] }
  [void]$hist.Add([pscustomobject]@{
    CardId = $CardId
    CardName = $CardName
    KeywordHint = $hint
    TitleSnippet = if ($Title.Length -gt 40) { $Title.Substring(0,40) } else { $Title }
    At = (Get-Date -Format 'o')
  })
  while ($hist.Count -gt 80) { $hist.RemoveAt(0) }
  # auto-grow rule if same hint→card seen ≥2
  if ($hint) {
    $same = @($hist | Where-Object {
      [string]$_.KeywordHint -eq $hint -and (
        ([string]$_.CardId -eq $CardId) -or ([string]$_.CardName -eq $CardName)
      )
    })
    if ($same.Count -ge 2) {
      $rlist = New-Object System.Collections.Generic.List[object]
      try { foreach ($r in @($rules.Rules)) { [void]$rlist.Add($r) } } catch { }
      $exists = $false
      foreach ($r in $rlist) {
        if ([string]$r.Keyword -eq $hint -and (
          ([string]$r.CardId -eq $CardId) -or ([string]$r.CardName -eq $CardName)
        )) { $exists = $true; break }
      }
      if (-not $exists) {
        [void]$rlist.Add([pscustomobject]@{
          Keyword = $hint; CardId = $CardId; CardName = $CardName; Weight = 28; Source = 'learn'
        })
      }
      $rules.Rules = @($rlist)
    }
  }
  $rules.History = @($hist)
  Save-TaskCardRules -Obj $rules
}

function Import-TaskCardsFromUia {
  # Best-effort: read ComboBox / list items whose name hints 과제카드 from Chrome/IE host
  $found = New-Object System.Collections.Generic.List[object]
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condChrome = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Window)
    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $condChrome)
    foreach ($w in $windows) {
      $wt = ''
      try { $wt = $w.Current.Name } catch { continue }
      if ($wt -notmatch 'Chrome|Edge|인터넷|업무|에듀파인|K-에듀|문서') { continue }
      $comboCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ComboBox)
      $combos = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $comboCond)
      foreach ($cb in $combos) {
        $cn = ''
        try { $cn = $cb.Current.Name } catch { $cn = '' }
        $looksTask = ($cn -match '과제|문서관리|카드')
        # also peek nearby label via HelpText
        $ht = ''
        try { $ht = $cb.Current.HelpText } catch { }
        if (-not $looksTask -and $ht -notmatch '과제|문서관리') {
          # still try if item count looks like task list
        }
        $items = @()
        try {
          $sel = $cb.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)
        } catch { $sel = $null }
        try {
          $expand = $null
          try {
            $expand = $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($expand) { $expand.Expand(); Start-Sleep -Milliseconds 200 }
          } catch { }
          $itemCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ListItem)
          $lis = $cb.FindAll([System.Windows.Automation.TreeScope]::Descendants, $itemCond)
          foreach ($li in $lis) {
            $nm = ''
            try { $nm = $li.Current.Name } catch { }
            if ($nm -and $nm.Trim().Length -ge 2 -and $nm -notmatch '선택|전체|없음') {
              $items += $nm.Trim()
            }
          }
          if ($expand) { try { $expand.Collapse() } catch { } }
        } catch { }
        if ($items.Count -ge 3 -and ($looksTask -or $items.Count -ge 5)) {
          $i = 0
          foreach ($nm in ($items | Select-Object -Unique)) {
            $i++
            [void]$found.Add([pscustomobject]@{
              Id = ('uia_{0}' -f $i)
              Name = $nm
              Keywords = @($nm -split '[\s/·]+' | Where-Object { $_.Length -ge 2 } | Select-Object -First 6)
            })
          }
          if ($found.Count -gt 0) { break }
        }
      }
      if ($found.Count -gt 0) { break }
    }
  } catch {
    return [pscustomobject]@{ Ok=$false; Count=0; Message=('UIA 가져오기 실패: {0}' -f $_.Exception.Message); Cards=@() }
  }
  if ($found.Count -eq 0) {
    return [pscustomobject]@{ Ok=$false; Count=0; Message='과제카드 드롭다운을 찾지 못했습니다. 문서관리카드 화면을 연 뒤 다시 시도하세요.'; Cards=@() }
  }
  Save-TaskCards -Cards @($found)
  return [pscustomobject]@{ Ok=$true; Count=$found.Count; Message=('{0}개 과제카드 가져옴 (로컬 저장)' -f $found.Count); Cards=@($found) }
}

function Set-UiaComboOrEditValue {
  param(
    [string]$Value,
    [string[]]$NameHints = @('과제카드','문서관리카드','과제')
  )
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return [pscustomobject]@{ Ok=$false; Message='값이 비었습니다.' }
  }
  # NEVER click 저장/접수/확인
  $blocked = '저장|접수|확인|상신|결재|발송|삭제'
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $winCond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Window)
    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)
    foreach ($w in $windows) {
      $wt = ''
      try { $wt = $w.Current.Name } catch { continue }
      if ($wt -notmatch 'Chrome|Edge|인터넷|업무|에듀파인|K-에듀|문서|접수') { continue }
      foreach ($hint in $NameHints) {
        $nameCond = New-Object System.Windows.Automation.PropertyCondition(
          [System.Windows.Automation.AutomationElement]::NameProperty, $hint,
          [System.Windows.Automation.PropertyConditionFlags]::IgnoreCase)
        # ComboBox by name
        $andCombo = New-Object System.Windows.Automation.AndCondition(
          (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ComboBox)),
          $nameCond)
        $cb = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $andCombo)
        if ($cb) {
          try {
            $expand = $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($expand) { $expand.Expand(); Start-Sleep -Milliseconds 250 }
          } catch { }
          $itemCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ListItem)
          $lis = $cb.FindAll([System.Windows.Automation.TreeScope]::Descendants, $itemCond)
          foreach ($li in $lis) {
            $nm = ''
            try { $nm = $li.Current.Name } catch { }
            if ($nm -eq $Value -or ($nm -and $nm -like ('*{0}*' -f $Value))) {
              try {
                $inv = $li.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($inv) { $inv.Select(); return [pscustomobject]@{ Ok=$true; Message=('과제카드 선택 채움: {0} (저장/접수 안 함)' -f $nm) } }
              } catch { }
              try {
                $ip = $li.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if ($ip) { $ip.Invoke(); return [pscustomobject]@{ Ok=$true; Message=('과제카드 선택 채움: {0} (저장/접수 안 함)' -f $nm) } }
              } catch { }
            }
          }
        }
        # Edit fallback
        $andEdit = New-Object System.Windows.Automation.AndCondition(
          (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)),
          $nameCond)
        $ed = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $andEdit)
        if ($ed) {
          try {
            $vp = $ed.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            if ($vp -and -not $vp.Current.IsReadOnly) {
              $vp.SetValue($Value)
              return [pscustomobject]@{ Ok=$true; Message=('과제카드 필드 채움: {0} (저장/접수 안 함)' -f $Value) }
            }
          } catch { }
        }
      }
    }
  } catch {
    return [pscustomobject]@{ Ok=$false; Message=('필드 채우기 실패: {0}' -f $_.Exception.Message) }
  }
  return [pscustomobject]@{ Ok=$false; Message='과제카드 필드를 찾지 못했습니다. 값이 클립보드에 있습니다. 저장/접수/확인은 누르지 않았습니다.' }
}

function Show-GongmunTaskCardDialog {
  param(
    [string]$Title = '',
    [string]$Body = ''
  )
  if (-not $Title -and -not $Body) {
    try {
      $clip = [System.Windows.Forms.Clipboard]::GetText()
      if ($clip) {
        $lines = @($clip -split "`r?`n")
        $Title = [string]$lines[0]
        if ($lines.Count -gt 1) { $Body = ($lines | Select-Object -Skip 1) -join "`n" }
      }
    } catch { }
  }
  $form = New-Object System.Windows.Forms.Form
  $form.Text = '공문접수 · 과제카드 추천'
  $form.Size = New-Object System.Drawing.Size(640, 520)
  $form.StartPosition = 'CenterParent'
  $form.Font = $script:UiFontUi
  $form.BackColor = $script:UiBg
  $form.ForeColor = $script:UiText
  $form.MinimizeBox = $false

  $root = New-Object System.Windows.Forms.TableLayoutPanel
  $root.Dock = 'Fill'
  $root.ColumnCount = 1
  $root.RowCount = 6
  $root.Padding = New-Object System.Windows.Forms.Padding(8)
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 70)))
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 110)))
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text = '공문 제목/본문 키워드로 과제카드 Top3 추천 · 저장/접수/확인 안 함'
  $lbl.AutoSize = $true
  $lbl.Font = $script:UiFontSection
  $lbl.ForeColor = $script:UiDanger

  $txtTitle = New-Object System.Windows.Forms.TextBox
  $txtTitle.Dock = 'Fill'
  $txtTitle.Text = $Title
  $txtTitle.Font = $script:UiFontUi

  $txtBody = New-Object System.Windows.Forms.TextBox
  $txtBody.Dock = 'Fill'
  $txtBody.Multiline = $true
  $txtBody.ScrollBars = 'Vertical'
  $txtBody.Text = $Body
  $txtBody.Font = $script:UiFontUi

  $lst = New-Object System.Windows.Forms.ListBox
  $lst.Dock = 'Fill'
  $lst.Font = $script:UiFontUi
  $script:GongmunCandidates = @()

  $refresh = {
    $script:GongmunCandidates = @(Match-TaskCards -Title $txtTitle.Text -Body $txtBody.Text -Top 3)
    $lst.Items.Clear()
    foreach ($c in $script:GongmunCandidates) {
      [void]$lst.Items.Add(('{0}%  {1}  ({2})' -f [int][Math]::Min(99, $c.Score), $c.Name, $c.Hits))
    }
    if ($lst.Items.Count -gt 0) { $lst.SelectedIndex = 0 }
  }

  $pnlBtn = New-Object System.Windows.Forms.FlowLayoutPanel
  $pnlBtn.AutoSize = $true
  $pnlBtn.Dock = 'Fill'
  $pnlBtn.WrapContents = $true

  $mkBtn = {
    param($text,$accent)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Height = 36
    $b.Width = 120
    $b.Margin = New-Object System.Windows.Forms.Padding(0,0,6,4)
    $b.FlatStyle = 'Flat'
    $b.Font = $script:UiFontBtn
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($accent) {
      $b.BackColor = $script:UiAccent
      $b.ForeColor = [System.Drawing.Color]::White
      $b.FlatAppearance.BorderSize = 0
    } else {
      $b.BackColor = $script:UiTile
      $b.ForeColor = $script:UiText
      $b.FlatAppearance.BorderSize = 0
    }
    return $b
  }

  $btnMatch = & $mkBtn '다시 추천' $false
  $btnImport = & $mkBtn 'UIA가져오기' $false
  $btnRule = & $mkBtn '규칙추가' $false
  $btnFill = & $mkBtn '필드채우기' $true
  $btnOpen = & $mkBtn '접수화면' $false
  $btnClose = & $mkBtn '닫기' $false

  $btnMatch.add_Click({ & $refresh })
  $btnImport.add_Click({
    $r = Import-TaskCardsFromUia
    [System.Windows.Forms.MessageBox]::Show($r.Message, '과제카드') | Out-Null
    & $refresh
  })
  $btnRule.add_Click({
    if ($lst.SelectedIndex -lt 0 -or $lst.SelectedIndex -ge $script:GongmunCandidates.Count) {
      [System.Windows.Forms.MessageBox]::Show('후보를 선택하세요.', '규칙') | Out-Null
      return
    }
    $pick = $script:GongmunCandidates[$lst.SelectedIndex]
    $kw = ''
    $toks = @(Get-TextTokens -Text $txtTitle.Text)
    if ($toks.Count -gt 0) { $kw = $toks[0] }
    $input = $kw
    try {
      Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue | Out-Null
      $input = [Microsoft.VisualBasic.Interaction]::InputBox('키워드 → 이 과제카드 규칙', '규칙추가', $kw)
    } catch {
      $input = $kw
    }
    if ([string]::IsNullOrWhiteSpace($input)) { return }
    $rules = Get-TaskCardRules
    $rlist = New-Object System.Collections.Generic.List[object]
    try { foreach ($r in @($rules.Rules)) { [void]$rlist.Add($r) } } catch { }
    [void]$rlist.Add([pscustomobject]@{
      Keyword=$input; CardId=$pick.Id; CardName=$pick.Name; Weight=30; Source='user'
    })
    $rules.Rules = @($rlist)
    Save-TaskCardRules -Obj $rules
    & $refresh
  })
  $btnFill.add_Click({
    if ($lst.SelectedIndex -lt 0 -or $lst.SelectedIndex -ge $script:GongmunCandidates.Count) {
      [System.Windows.Forms.MessageBox]::Show('후보를 선택하세요.', '채우기') | Out-Null
      return
    }
    $pick = $script:GongmunCandidates[$lst.SelectedIndex]
    Record-TaskCardPick -CardId $pick.Id -CardName $pick.Name -Title $txtTitle.Text -Body $txtBody.Text
    try { [System.Windows.Forms.Clipboard]::SetText([string]$pick.Name) } catch { }
    $r = Set-UiaComboOrEditValue -Value $pick.Name
    [System.Windows.Forms.MessageBox]::Show($r.Message, '공문접수') | Out-Null
  })
  $btnOpen.add_Click({
    if (Get-Command Open-InChrome -ErrorAction SilentlyContinue) {
      Open-InChrome -Url $script:GongmunRecvUrl
    } else { Start-Process $script:GongmunRecvUrl | Out-Null }
  })
  $btnClose.add_Click({ $form.Close() })

  foreach ($b in @($btnMatch,$btnImport,$btnRule,$btnFill,$btnOpen,$btnClose)) {
    [void]$pnlBtn.Controls.Add($b)
  }

  $lblNote = New-Object System.Windows.Forms.Label
  $lblNote.Text = '로컬 JSON만 사용. 최상위 후보가 미리 선택됩니다. 저장·접수·확인·상신은 절대 클릭하지 않습니다.'
  $lblNote.AutoSize = $true
  $lblNote.ForeColor = $script:UiMuted

  [void]$root.Controls.Add($lbl, 0, 0)
  [void]$root.Controls.Add($txtTitle, 0, 1)
  [void]$root.Controls.Add($txtBody, 0, 2)
  [void]$root.Controls.Add($lst, 0, 3)
  [void]$root.Controls.Add($pnlBtn, 0, 4)
  [void]$root.Controls.Add($lblNote, 0, 5)
  $form.Controls.Add($root)

  try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch { }
  & $refresh
  if ($script:GongmunCandidates.Count -gt 0) {
    # preselect best
    $lst.SelectedIndex = 0
  }
  [void]$form.ShowDialog()
}

function Invoke-GongmunRecvAssist {
  param([string]$Title = '', [string]$Body = '')
  if (-not $Title) {
    $a = $null
    if (Get-Command Get-SelectedAlert -ErrorAction SilentlyContinue) {
      try { $a = Get-SelectedAlert } catch { }
    }
    if ($null -ne $a) {
      $Title = [string]$a.Title
      $Body = [string]$a.Body
    }
  }
  Show-GongmunTaskCardDialog -Title $Title -Body $Body
  return [pscustomobject]@{ Ok=$true; Message='공문접수 과제카드 도우미 종료 (저장/접수 안 함)' }
}
