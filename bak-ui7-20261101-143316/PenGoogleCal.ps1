# PenGoogleCal.ps1 — Google Calendar via Chrome TEMPLATE URL + UIA '저장' click.
# No OAuth / no Google API. Dot-sourced by PenHelper.
# Saved event ids: %LOCALAPPDATA%\PenHelper\gcal_saved.json (never secrets).

Set-StrictMode -Version Latest

$script:GCalSavedPath = Join-Path $script:DataDir 'gcal_saved.json'

function Get-GCalSavedMap {
  $data = Read-JsonFile -Path $script:GCalSavedPath -Default $null
  $map = @{}
  if ($null -eq $data) { return $map }
  if ($data -is [System.Management.Automation.PSCustomObject]) {
    foreach ($p in $data.PSObject.Properties) { $map[$p.Name] = $p.Value }
  } elseif ($data -is [hashtable]) {
    foreach ($k in $data.Keys) { $map[[string]$k] = $data[$k] }
  }
  return $map
}

function Save-GCalSavedMap {
  param($Map)
  Write-JsonFile -Path $script:GCalSavedPath -Object $Map
}

function Test-GCalItemSaved {
  param([string]$ItemId)
  if ([string]::IsNullOrWhiteSpace($ItemId)) { return $false }
  $map = Get-GCalSavedMap
  return $map.ContainsKey($ItemId)
}

function Set-GCalItemSaved {
  param([string]$ItemId, [string]$Title = '', [string]$DateYmd = '', [string]$Note = '')
  $map = Get-GCalSavedMap
  $map[$ItemId] = [pscustomobject]@{
    SavedAt = (Get-Date -Format 'o')
    Title   = $Title
    Date    = $DateYmd
    Note    = $Note
  }
  Save-GCalSavedMap -Map $map
}

function Mask-GCalText {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return '' }
  if (Get-Command Mask-PersonalInfo -ErrorAction SilentlyContinue) {
    $mt = Mask-PersonalInfo -Text $Text
    if ($mt -and $mt.PSObject.Properties['Masked']) { return [string]$mt.Masked }
    if ($mt -is [string]) { return $mt }
  }
  return $Text
}

function New-GCalTemplateUrl {
  param([string]$Title, [string]$DateYmd, [string]$Details)
  try {
    $d = [datetime]::ParseExact($DateYmd, 'yyyy-MM-dd', $null)
  } catch { $d = (Get-Date).Date }
  $start = $d.ToString('yyyyMMdd')
  $end = $d.AddDays(1).ToString('yyyyMMdd')
  $t = [uri]::EscapeDataString($(if ($Title) { $Title } else { '일정' }))
  $det = [uri]::EscapeDataString($(if ($Details) { $Details } else { '' }))
  return ('https://calendar.google.com/calendar/render?action=TEMPLATE&text={0}&dates={1}/{2}&details={3}' -f $t, $start, $end, $det)
}

function Get-ChromeMainWindows {
  param([switch]$AnyChrome)
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window)
  $col = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
  $out = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $col.Count; $i++) {
    $w = $col.Item($i)
    try {
      $name = [string]$w.Current.Name
      $cls = [string]$w.Current.ClassName
      if ($cls -notmatch 'Chrome_WidgetWin') { continue }
      if (-not $AnyChrome) {
        if ($name -and ($name -match '캘린더|Calendar|Google|이벤트|Event|일정')) {
          [void]$out.Add($w)
        }
      } else {
        [void]$out.Add($w)
      }
    } catch { }
  }
  # return ArrayList so callers can foreach items (avoid unary-comma wrap)
  return $out
}

function Get-GCalTargetWindow {
  param([switch]$PreferWithSave)
  $cals = @(Get-ChromeMainWindows)
  $any = @(Get-ChromeMainWindows -AnyChrome)
  $candidates = @()
  if ($cals.Count -gt 0) { $candidates += $cals }
  foreach ($w in $any) {
    $dup = $false
    foreach ($c in $candidates) {
      try { if ($c.Current.NativeWindowHandle -eq $w.Current.NativeWindowHandle) { $dup = $true; break } } catch { }
    }
    if (-not $dup) { $candidates += $w }
  }
  if ($PreferWithSave) {
    foreach ($w in $candidates) {
      $btn = Find-GCalSaveButton -Root $w -TimeoutMs 300
      if ($null -ne $btn) { return $w }
    }
  }
  if ($cals.Count -gt 0) { return $cals[0] }
  foreach ($w in $any) {
    try {
      $n = [string]$w.Current.Name
      if ($n -match '캘린더|Calendar|Google|이벤트|Event|일정|새 일정|Create') { return $w }
    } catch { }
  }
  if ($any.Count -gt 0) { return $any[$any.Count - 1] }
  return $null
}

function Find-GCalSaveButton {
  param($Root, [int]$TimeoutMs = 20000)
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  $btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
  while ((Get-Date) -lt $deadline) {
    try {
      $btns = @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond))
      foreach ($b in $btns) {
        $n = ''
        try { $n = [string]$b.Current.Name } catch { continue }
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        # exact Save on event editor — not 임시저장 etc.
        if ($n -eq '저장' -or $n -eq 'Save' -or $n -eq 'Save changes') {
          return $b
        }
      }
      # broader: name ends with 저장 / is Save
      foreach ($b in $btns) {
        $n = ''
        try { $n = [string]$b.Current.Name } catch { continue }
        if ($n -match '임시|자동|다른 이름으로') { continue }
        if ($n -match '^(저장|Save)$' -or $n -eq '저장(S)' ) { return $b }
      }
    } catch { }
    Start-Sleep -Milliseconds 400
  }
  return $null
}

function Invoke-UiaButton {
  param($Element)
  if ($null -eq $Element) { return $false }
  try {
    $pat = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    if ($null -ne $pat) { $pat.Invoke(); return $true }
  } catch { }
  try {
    # fallback: set focus + Enter
    $Element.SetFocus()
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    return $true
  } catch { return $false }
}

function Wait-GCalSavedSignal {
  param($Root, [string]$ExpectTitle, [int]$TimeoutMs = 15000)
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  while ((Get-Date) -lt $deadline) {
    try {
      $name = [string]$Root.Current.Name
      # after save, title often returns to Calendar / 캘린더 without "새 일정" edit chrome
      if ($name -match 'Google 캘린더|Google Calendar|캘린더 -' -and $name -notmatch '이벤트 세부|Event details|새 일정') {
        return [pscustomobject]@{ Ok = $true; How = 'title' }
      }
      # toast / status text
      $textCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Text)
      $texts = @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond))
      foreach ($t in $texts) {
        $tn = ''
        try { $tn = [string]$t.Current.Name } catch { continue }
        if ($tn -match '일정이 저장|Event saved|Saved|저장됨|일정을 저장') {
          return [pscustomobject]@{ Ok = $true; How = 'toast'; Text = $tn }
        }
      }
      # edit dialog gone: no 저장 button
      $btn = Find-GCalSaveButton -Root $Root -TimeoutMs 200
      if ($null -eq $btn -and $name -match '캘린더|Calendar') {
        return [pscustomobject]@{ Ok = $true; How = 'no-save-btn' }
      }
    } catch { }
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{ Ok = $false; How = 'timeout' }
}

function Open-GCalTemplateInChrome {
  param([string]$Url)
  $chrome = $null
  foreach ($c in @(
      "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )) {
    if (Test-Path -LiteralPath $c) { $chrome = $c; break }
  }
  if ($chrome) {
    # reuse existing profile/session
    Start-Process -FilePath $chrome -ArgumentList @('--new-window', $Url) | Out-Null
  } elseif (Get-Command Open-InChrome -ErrorAction SilentlyContinue) {
    Open-InChrome -Url $Url
  } else {
    Start-Process $Url | Out-Null
  }
}

function Save-ScheduleToGoogleCalendar {
  param(
    [string]$ItemId,
    [string]$Title,
    [string]$DateYmd,
    [string]$Body = ''
  )
  if ([string]::IsNullOrWhiteSpace($ItemId)) {
    return [pscustomobject]@{ Ok = $false; Message = 'ItemId 없음'; Chip = $null }
  }
  if (Test-GCalItemSaved -ItemId $ItemId) {
    return [pscustomobject]@{
      Ok = $true; Already = $true
      Message = '구글 캘린더에 저장됨'
      Chip = '구글 캘린더에 저장됨'
    }
  }

  $maskTitle = Mask-GCalText -Text $Title
  $maskBody = Mask-GCalText -Text $Body
  if ($maskTitle.Length -gt 120) { $maskTitle = $maskTitle.Substring(0, 120) }
  if ($maskBody.Length -gt 400) { $maskBody = $maskBody.Substring(0, 400) }
  if ([string]::IsNullOrWhiteSpace($maskTitle)) { $maskTitle = '일정' }

  $url = New-GCalTemplateUrl -Title $maskTitle -DateYmd $DateYmd -Details $maskBody
  Open-GCalTemplateInChrome -Url $url

  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue | Out-Null
  # wait until a Chrome window exposes the event-edit Save button
  $win = $null
  $saveBtn = $null
  $deadline = (Get-Date).AddSeconds(35)
  while ((Get-Date) -lt $deadline -and $null -eq $saveBtn) {
    $cands = @()
    $cands += @(Get-ChromeMainWindows)
    $cands += @(Get-ChromeMainWindows -AnyChrome)
    $seen = @{}
    foreach ($cand in $cands) {
      try {
        $h = [string]$cand.Current.NativeWindowHandle
        if ($seen.ContainsKey($h)) { continue }
        $seen[$h] = $true
        $n = [string]$cand.Current.Name
        # skip unrelated chrome apps
        if ($n -and $n -notmatch '캘린더|Calendar|Google|이벤트|Event|일정' -and $n -match 'Grok|Claude|ChatGPT') { continue }
        $btn = Find-GCalSaveButton -Root $cand -TimeoutMs 400
        if ($null -ne $btn) {
          $win = $cand
          $saveBtn = $btn
          break
        }
        # remember likely edit window even if button not yet painted
        if ($null -eq $win -and $n -match '세부|details|이벤트|Event|새 일정|Create') {
          $win = $cand
        }
      } catch { }
    }
    if ($null -eq $saveBtn) { Start-Sleep -Milliseconds 450 }
  }
  if ($null -eq $win -and $null -eq $saveBtn) {
    return [pscustomobject]@{
      Ok = $false
      Message = 'Chrome 구글 캘린더 창을 찾지 못했습니다. Chrome에 캘린더 로그인 상태를 확인하세요.'
      Chip = $null
    }
  }
  if ($null -eq $win) { $win = Get-GCalTargetWindow }

  try {
    $win.SetFocus()
  } catch { }

  if ($null -eq $saveBtn) {
    $saveBtn = Find-GCalSaveButton -Root $win -TimeoutMs 20000
  }
  if ($null -eq $saveBtn) {
    # last sweep across all chrome
    foreach ($cand in @(Get-ChromeMainWindows -AnyChrome)) {
      $saveBtn = Find-GCalSaveButton -Root $cand -TimeoutMs 500
      if ($null -ne $saveBtn) { $win = $cand; break }
    }
  }
  if ($null -eq $saveBtn) {
    return [pscustomobject]@{
      Ok = $false
      Message = "템플릿은 열렸으나 '저장' 버튼을 찾지 못했습니다. 캘린더 편집 화면에서 수동 저장하세요."
      Chip = $null
      Url = $url
    }
  }

  if (-not (Invoke-UiaButton -Element $saveBtn)) {
    return [pscustomobject]@{ Ok = $false; Message = '저장 버튼 클릭 실패'; Chip = $null }
  }

  Start-Sleep -Milliseconds 800
  $win2 = Get-GCalTargetWindow
  if ($null -eq $win2) { $win2 = $win }
  $ver = Wait-GCalSavedSignal -Root $win2 -ExpectTitle $maskTitle -TimeoutMs 18000
  if (-not $ver.Ok) {
    return [pscustomobject]@{
      Ok = $false
      Message = '저장 클릭 후 확인(토스트/캘린더 복귀) 실패. 화면에 일정이 생겼는지 확인하세요.'
      Chip = $null
    }
  }

  Set-GCalItemSaved -ItemId $ItemId -Title $maskTitle -DateYmd $DateYmd -Note $ver.How
  return [pscustomobject]@{
    Ok = $true
    Message = '구글 캘린더에 저장됨'
    Chip = '구글 캘린더에 저장됨'
    Title = $maskTitle
    Date = $DateYmd
    How = $ver.How
  }
}
