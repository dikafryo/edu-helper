# --- loaded from PenHelper: call Add-NoticePage -HostPanel $page ---
function Add-NoticePage {
  param($HostPanel)

  $script:MoreGridMap = @{}
  $script:LastAttachInfo = $null
  $script:LastAttachSave = $null
  $tt = New-Object System.Windows.Forms.ToolTip
  $tt.AutoPopDelay = 8000
  $tt.InitialDelay = 400
  $script:NoticeToolTip = $tt

  # ---- shared chrome helpers ----
  function New-StepCard {
    param([string]$Title)
    $card = New-Object System.Windows.Forms.Panel
    $card.AutoSize = $false
    $card.Padding = New-Object System.Windows.Forms.Padding(16)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
    $card.BackColor = [System.Drawing.Color]::White
    $card.Tag = 'card'
    $card.add_Paint({
      param($s, $e)
      $pen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')), 1
      $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1)
      $pen.Dispose()
    })
    $inner = New-Object System.Windows.Forms.FlowLayoutPanel
    $inner.FlowDirection = 'TopDown'
    $inner.WrapContents = $false
    $inner.AutoSize = $true
    $inner.Dock = 'Top'
    $inner.BackColor = [System.Drawing.Color]::White
    $inner.Tag = 'card'
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $Title
    $h.AutoSize = $true
    $h.Font = New-Object System.Drawing.Font('맑은 고딕', 13, [System.Drawing.FontStyle]::Bold)
    $h.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
    $h.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $h.Tag = 'stephead'
    [void]$inner.Controls.Add($h)
    [void]$card.Controls.Add($inner)
    return @{ Card = $card; Inner = $inner; Header = $h }
  }

  function New-TileBtn {
    param(
      [string]$Text,
      [string]$Emoji = '',
      [string]$Hex = '#E5E5EA',
      [switch]$Secondary,
      [switch]$Accent,
      [string]$DotHex = '',
      [string]$Tip = ''
    )
    $b = New-Object System.Windows.Forms.Button
    $label = if ($Emoji) { ("{0}`r`n{1}" -f $Emoji, $Text) } else { $Text }
    if ($DotHex) { $label = ("● {0}" -f $Text) }
    $b.Text = $label
    $b.Size = New-Object System.Drawing.Size(110, 80)
    $b.Margin = New-Object System.Windows.Forms.Padding(4)
    $b.FlatStyle = 'Flat'
    $b.Font = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    $b.TextAlign = 'MiddleCenter'
    if ($Accent) {
      $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
      $b.ForeColor = [System.Drawing.Color]::White
      $b.FlatAppearance.BorderSize = 0
      $b.Tag = 'uicolor:#007AFF;tile;radius12'
    } elseif ($Secondary) {
      $b.BackColor = [System.Drawing.Color]::White
      $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
      $b.FlatAppearance.BorderSize = 1
      $b.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
      $b.Tag = 'uicolor:#FFFFFF;outline;tile;radius12'
    } else {
      # calculator key
      $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
      $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
      $b.FlatAppearance.BorderSize = 0
      $b.Tag = 'uicolor:#E5E5EA;tile;radius12'
    }
    if ($DotHex) {
      $b.add_Paint({
        param($s, $e)
        $hx = [string]$s.Name
        if ($hx -like 'dot:*') {
          $col = [System.Drawing.ColorTranslator]::FromHtml($hx.Substring(4))
          $brush = New-Object System.Drawing.SolidBrush $col
          $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
          $e.Graphics.FillEllipse($brush, 10, 10, 10, 10)
          $brush.Dispose()
        }
      })
      $b.Name = ('dot:{0}' -f $DotHex)
      $b.Text = $Text
      $b.TextAlign = 'MiddleCenter'
      $b.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    }
    if ($Tip) { $script:NoticeToolTip.SetToolTip($b, $Tip) }
    if (Get-Command Set-RoundedRegion -ErrorAction SilentlyContinue) {
      Set-RoundedRegion -Control $b -Radius 12
      $b.add_Resize({ Set-RoundedRegion -Control $this -Radius 12 })
    }
    return $b
  }

  function New-TileGrid {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.AutoSize = $true
    $f.AutoSizeMode = 'GrowAndShrink'
    $f.WrapContents = $true
    $f.FlowDirection = 'LeftToRight'
    $f.Padding = New-Object System.Windows.Forms.Padding(0)
    $f.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $f.BackColor = [System.Drawing.Color]::White
    $f.Tag = 'tilegrid'
    return $f
  }

  function New-MoreBlock {
    param($Inner, $Primary, $Secondary)
    $gridP = New-TileGrid
    foreach ($b in @($Primary)) { if ($null -ne $b) { [void]$gridP.Controls.Add($b) } }
    [void]$Inner.Controls.Add($gridP)
    $secs = @($Secondary)
    if (@($secs).Count -eq 0) { return }
    $btnMore = New-Object System.Windows.Forms.Button
    $btnMore.Text = '▾ 더보기'
    $btnMore.AutoSize = $true
    $btnMore.FlatStyle = 'Flat'
    $btnMore.FlatAppearance.BorderSize = 0
    $btnMore.BackColor = [System.Drawing.Color]::White
    $btnMore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6E6E73')
    $btnMore.Font = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
    $btnMore.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnMore.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 4)
    $btnMore.Height = 28
    $gridS = New-TileGrid
    $gridS.Visible = $false
    foreach ($b in $secs) { if ($null -ne $b) { [void]$gridS.Controls.Add($b) } }
    $moreId = [guid]::NewGuid().ToString('N')
    $btnMore.Name = ('more_' + $moreId)
    $script:MoreGridMap[$btnMore.Name] = $gridS
    $btnMore.add_Click({
      param($s,$e)
      $grid = $script:MoreGridMap[$s.Name]
      if ($null -eq $grid) { return }
      $grid.Visible = -not $grid.Visible
      $s.Text = if ($grid.Visible) { '▴ 접기' } else { '▾ 더보기' }
      if ($script:NoticeFitChrome) { & $script:NoticeFitChrome }
    })
    $btnMore.Tag = 'morelink'
    [void]$Inner.Controls.Add($btnMore)
    [void]$Inner.Controls.Add($gridS)
  }

  $script:lblNStatus = New-Object System.Windows.Forms.Label
  $script:lblNStatus.Dock = 'Bottom'
  $script:lblNStatus.Height = 28
  $script:lblNStatus.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
  $script:lblNStatus.Text = '안내공문: 원문창을 고른 뒤 타일을 누르세요'
  $script:lblNStatus.Font = New-Object System.Drawing.Font('맑은 고딕', 9)
  $script:lblNStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $script:lblNStatus.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
  $script:lblNStatus.Tag = 'statusbar'

  $pnlScroll = New-Object System.Windows.Forms.Panel
  $pnlScroll.Dock = 'Fill'
  $pnlScroll.AutoScroll = $true
  $pnlScroll.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7')
  $pnlScroll.Tag = 'bg'
  $pnlScroll.Padding = New-Object System.Windows.Forms.Padding(16)

  $cGray = '#E5E5EA'; $cBlue = '#007AFF'; $cPurple = '#AF52DE'
  $cGreen = '#34C759'; $cOrange = '#FF9500'; $cTeal = '#30B0C7'  # category dot only

  # ===== ① 불러오기 =====
  $s1 = New-StepCard '① 불러오기'
  $grid1 = New-TileGrid
  $btnNRefresh = New-TileBtn -Text '창새로고침' -Emoji '⟳' -Secondary -Tip '원문·기안 창 목록을 다시 읽습니다'
  $btnNRead = New-TileBtn -Text '원문읽기' -Emoji '▣' -Tip '선택한 원문창에서 제목·본문을 읽습니다'
  foreach ($b in @($btnNRefresh, $btnNRead)) { [void]$grid1.Controls.Add($b) }
  [void]$s1.Inner.Controls.Add($grid1)
  $rowWin = New-Object System.Windows.Forms.FlowLayoutPanel
  $rowWin.FlowDirection = 'TopDown'
  $rowWin.WrapContents = $false
  $rowWin.AutoSize = $true
  $rowWin.AutoSizeMode = 'GrowAndShrink'
  $rowWin.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
  $rowWin.BackColor = [System.Drawing.Color]::White
  $rowWin.Tag = 'fullrow'
  $lblNWin = New-Object System.Windows.Forms.Label; $lblNWin.Text = '원문'; $lblNWin.AutoSize = $true
  $lblNWin.Font = New-Object System.Drawing.Font('맑은 고딕', 11); $lblNWin.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $lblNWin.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 2)
  $script:cboNSrc = New-Object System.Windows.Forms.ComboBox
  $script:cboNSrc.DropDownStyle = 'DropDownList'
  $script:cboNSrc.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:cboNSrc.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $script:cboNSrc.Tag = 'fullcombo'
  $lblNTmpl = New-Object System.Windows.Forms.Label; $lblNTmpl.Text = '기안'; $lblNTmpl.AutoSize = $true
  $lblNTmpl.Font = New-Object System.Drawing.Font('맑은 고딕', 11); $lblNTmpl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $lblNTmpl.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 2)
  $script:cboNTmpl = New-Object System.Windows.Forms.ComboBox
  $script:cboNTmpl.DropDownStyle = 'DropDownList'
  $script:cboNTmpl.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:cboNTmpl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $script:cboNTmpl.Tag = 'fullcombo'
  foreach ($c in @($lblNWin, $script:cboNSrc, $lblNTmpl, $script:cboNTmpl)) { [void]$rowWin.Controls.Add($c) }
  [void]$s1.Inner.Controls.Add($rowWin)
  $script:NoticeRowWin = $rowWin

  # ===== ② 작성 =====
  $s2 = New-StepCard '② 작성'
  $btnNOneShot = New-TileBtn -Text '안내공문' -Emoji '⚡' -Accent -Tip '원문읽기→로컬초안→제목·본문 기안창 채우기 (한 번에)'
  $btnNLocal = New-TileBtn -Text '로컬초안' -Emoji '✎' -Secondary -Tip '안내공문 초안만 만들고 미리보기에 넣습니다'
  $btnNTitle = New-TileBtn -Text '제목넣기' -Emoji '▸' -Secondary -Tip '기안창 제목칸에 제목을 넣습니다'
  $btnNBody = New-TileBtn -Text '본문넣기' -Emoji '▤' -Secondary -Tip '기안창 본문(HWP)에 붙여넣습니다. 응답 없는 창은 건드리지 않습니다'
  New-MoreBlock -Inner $s2.Inner -Primary @($btnNOneShot) -Secondary @($btnNLocal, $btnNTitle, $btnNBody)

  # 서식 옵션 row
  $optRow = New-Object System.Windows.Forms.FlowLayoutPanel
  $optRow.AutoSize = $true; $optRow.WrapContents = $true; $optRow.BackColor = [System.Drawing.Color]::White; $optRow.Tag = 'card'
  $optRow.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
  $lblOpt = New-Object System.Windows.Forms.Label
  $lblOpt.Text = '서식 옵션'; $lblOpt.AutoSize = $true
  $lblOpt.Font = New-Object System.Drawing.Font('맑은 고딕', 11, [System.Drawing.FontStyle]::Bold)
  $lblOpt.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
  $lblOpt.Margin = New-Object System.Windows.Forms.Padding(0, 6, 16, 6)
  $script:chkTighten = New-Object System.Windows.Forms.CheckBox
  $script:chkTighten.Text = '자간줄이기'; $script:chkTighten.AutoSize = $true
  $script:chkTighten.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:chkTighten.Margin = New-Object System.Windows.Forms.Padding(8, 6, 16, 6)
  $script:chkTighten.Checked = [bool]$script:Settings.TightenLetterSpacing
  $script:chkTighten.add_CheckedChanged({
    $script:Settings.TightenLetterSpacing = $script:chkTighten.Checked
    Save-PenSettings -Settings $script:Settings
  })
  $script:chkInTable = New-Object System.Windows.Forms.CheckBox
  $script:chkInTable.Text = '표 안 입력'; $script:chkInTable.AutoSize = $true
  $script:chkInTable.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:chkInTable.Margin = New-Object System.Windows.Forms.Padding(8, 6, 16, 6)
  $script:chkInTable.Checked = [bool]$script:Settings.BodyFillInTable
  $script:chkInTable.add_CheckedChanged({
    $script:Settings.BodyFillInTable = $script:chkInTable.Checked
    Save-PenSettings -Settings $script:Settings
  })
  $script:chkFont = New-Object System.Windows.Forms.CheckBox
  $script:chkFont.Text = '굴림 12pt'; $script:chkFont.AutoSize = $true
  $script:chkFont.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:chkFont.Margin = New-Object System.Windows.Forms.Padding(8, 6, 16, 6)
  $script:chkFont.Checked = [bool]$script:Settings.ApplyBodyFont
  $script:chkFont.add_CheckedChanged({
    $script:Settings.ApplyBodyFont = $script:chkFont.Checked
    Save-PenSettings -Settings $script:Settings
  })
  foreach ($c in @($lblOpt, $script:chkTighten, $script:chkInTable, $script:chkFont)) { [void]$optRow.Controls.Add($c) }
  [void]$s2.Inner.Controls.Add($optRow)

  # ===== 그록 (더보기 성격이지만 워크플로 중간 유지 — 작은 카드) =====
  $sG = New-StepCard '그록 (선택)'
  $gridG = New-TileGrid
  $btnNGrok = New-TileBtn -Text '다듬기' -Emoji '★' -DotHex $cPurple -Tip '마스킹 후 그록에 붙여넣을 텍스트를 만듭니다'
  $btnNGrokPaste = New-TileBtn -Text '결과넣기' -Emoji '⇩' -Secondary -Tip '클립보드의 그록 결과를 복원해 미리보기에 넣습니다'
  foreach ($b in @($btnNGrok, $btnNGrokPaste)) { [void]$gridG.Controls.Add($b) }
  [void]$sG.Inner.Controls.Add($gridG)

  # ===== ③ 결재·수신 =====
  $s3 = New-StepCard '③ 결재·수신'
  $btnNAppr = New-TileBtn -Text '결재선' -Emoji '✓' -DotHex $cGreen -Tip '저장결재선 창을 엽니다 (결재올림 금지)'
  $btnNRecv = New-TileBtn -Text '수신처' -Emoji '✉' -DotHex $cGreen -Tip '저장수신처 창을 엽니다 (발송 금지)'
  $btnNPresetSave = New-TileBtn -Text '프리셋' -Emoji '⇩' -Secondary -Tip '현재 결재선·수신처 이름을 저장합니다'
  $btnNSync = New-TileBtn -Text '동기화' -Emoji '⟳' -Secondary -Tip '포털 목록을 읽어 프리셋에 후보를 넣습니다'
  New-MoreBlock -Inner $s3.Inner -Primary @($btnNAppr, $btnNRecv) -Secondary @($btnNPresetSave, $btnNSync)
  $flowApprCombo = New-Object System.Windows.Forms.FlowLayoutPanel
  $flowApprCombo.AutoSize = $true; $flowApprCombo.WrapContents = $true
  $flowApprCombo.BackColor = [System.Drawing.Color]::White; $flowApprCombo.Tag = 'card'
  $flowApprCombo.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
  $lblAp = New-Object System.Windows.Forms.Label; $lblAp.Text = '결재선'; $lblAp.AutoSize = $true
  $lblAp.Font = New-Object System.Drawing.Font('맑은 고딕', 11); $lblAp.Margin = New-Object System.Windows.Forms.Padding(0, 8, 8, 4)
  $script:cboAppr = New-Object System.Windows.Forms.ComboBox
  $script:cboAppr.Width = 180; $script:cboAppr.DropDownStyle = 'DropDown'
  $script:cboAppr.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:cboAppr.Margin = New-Object System.Windows.Forms.Padding(4, 4, 16, 4)
  $lblRc = New-Object System.Windows.Forms.Label; $lblRc.Text = '수신처'; $lblRc.AutoSize = $true
  $lblRc.Font = New-Object System.Drawing.Font('맑은 고딕', 11); $lblRc.Margin = New-Object System.Windows.Forms.Padding(0, 8, 8, 4)
  $script:cboRecv = New-Object System.Windows.Forms.ComboBox
  $script:cboRecv.Width = 180; $script:cboRecv.DropDownStyle = 'DropDown'
  $script:cboRecv.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:cboRecv.Margin = New-Object System.Windows.Forms.Padding(4, 4, 16, 4)
  $lblNHint = New-Object System.Windows.Forms.Label
  $lblNHint.Text = '※ 결재올림/발송 안 함'; $lblNHint.AutoSize = $true
  $lblNHint.ForeColor = [System.Drawing.Color]::DarkRed
  $lblNHint.Font = New-Object System.Drawing.Font('맑은 고딕', 10)
  $lblNHint.Margin = New-Object System.Windows.Forms.Padding(8, 8, 4, 4)
  foreach ($c in @($lblAp, $script:cboAppr, $lblRc, $script:cboRecv, $lblNHint)) { [void]$flowApprCombo.Controls.Add($c) }
  [void]$s3.Inner.Controls.Add($flowApprCombo)

  # ===== ④ 붙임 =====
  $s4 = New-StepCard '④ 붙임'
  $btnNAttachSave = New-TileBtn -Text '붙임저장' -Emoji '⧉' -DotHex $cOrange -Tip '붙임 목록을 읽고 로컬에 저장합니다'
  $btnNAttachPut = New-TileBtn -Text '첨부준비' -Emoji '▦' -Secondary -Tip '기안 첨부 드라이런 (실실행 전 확인)'
  New-MoreBlock -Inner $s4.Inner -Primary @($btnNAttachSave) -Secondary @($btnNAttachPut)

  # ===== 미리보기 =====
  $sP = New-StepCard '미리보기'
  $sP.Card.AutoSize = $false
  $sP.Card.Height = 220
  $script:txtNotice = New-Object System.Windows.Forms.TextBox
  $script:txtNotice.Multiline = $true
  $script:txtNotice.ScrollBars = 'Vertical'
  $script:txtNotice.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
  $script:txtNotice.AcceptsReturn = $true
  $script:txtNotice.BorderStyle = 'FixedSingle'
  $script:txtNotice.Dock = 'Fill'
  $script:txtNotice.Height = 160
  # rebuild preview card: header top, text fill
  $sP.Card.Controls.Clear()
  $sP.Header.Dock = 'Top'
  $script:txtNotice.Dock = 'Fill'
  [void]$sP.Card.Controls.Add($script:txtNotice)
  [void]$sP.Card.Controls.Add($sP.Header)

  $script:NoticeChromeCards = @($s1.Card, $s2.Card, $sG.Card, $s3.Card, $s4.Card, $sP.Card)
  $script:NoticeScrollHost = $pnlScroll
  for ($i = $script:NoticeChromeCards.Count - 1; $i -ge 0; $i--) {
    $card = $script:NoticeChromeCards[$i]
    $card.Dock = 'Top'
    $card.AutoSize = $false
    $card.Region = $null
    if ($i -eq ($script:NoticeChromeCards.Count - 1)) { $card.Height = 260 } else { $card.Height = 180 }
    [void]$pnlScroll.Controls.Add($card)
  }
  function script:Stretch-NoticeTree {
    param($Root, [int]$InnerW)
    if ($null -eq $Root) { return }
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
      $n = $queue.Dequeue()
      foreach ($ch in @($n.Controls)) { $queue.Enqueue($ch) }
      $tag = [string]$n.Tag
      if ($n -is [System.Windows.Forms.FlowLayoutPanel]) {
        $n.Width = $InnerW
        $n.MaximumSize = New-Object System.Drawing.Size($InnerW, 100000)
        if ($n.Dock -ne 'Top') { $n.Dock = 'Top' }
      }
      if ($n -is [System.Windows.Forms.ComboBox] -and ($tag -eq 'fullcombo')) {
        $n.Width = [Math]::Max(200, $InnerW - 8)
      }
      if ($n -is [System.Windows.Forms.ComboBox] -and ($n -eq $script:cboAppr -or $n -eq $script:cboRecv)) {
        $n.Width = [Math]::Max(180, [Math]::Min(360, $InnerW - 40))
      }
    }
  }
  $fitChrome = {
    try {
      $hostW = $script:NoticeScrollHost.ClientSize.Width
      if ($hostW -le 40) { return }
      $innerW = [Math]::Max(300, $hostW - 40)
      $script:NoticeScrollHost.SuspendLayout()
      foreach ($c in @($script:NoticeChromeCards)) {
        if ($null -eq $c) { continue }
        $c.SuspendLayout()
        $c.Dock = 'Top'
        $c.AutoSize = $false
        $c.Region = $null
        $c.Width = $hostW
        script:Stretch-NoticeTree -Root $c -InnerW $innerW
        $inner = $null
        foreach ($ch in @($c.Controls)) {
          if ($ch -is [System.Windows.Forms.FlowLayoutPanel]) { $inner = $ch; break }
        }
        if ($c -eq $script:NoticeChromeCards[-1]) {
          $c.Height = 260
        } elseif ($null -ne $inner) {
          $inner.Width = $innerW
          $pref = $inner.GetPreferredSize((New-Object System.Drawing.Size($innerW, 0)))
          $c.Height = [Math]::Max(100, $pref.Height + $c.Padding.Top + $c.Padding.Bottom + 12)
        }
        $c.ResumeLayout($true)
      }
      $script:NoticeScrollHost.ResumeLayout($true)
    } catch {
      try { $script:lblNStatus.Text = ('레이아웃: ' + $_.Exception.Message) } catch { }
    }
  }
  $script:NoticeFitChrome = $fitChrome
  $pnlScroll.add_Resize({ if ($script:NoticeFitChrome) { & $script:NoticeFitChrome } })
  $HostPanel.add_Resize({ if ($script:NoticeFitChrome) { & $script:NoticeFitChrome } })
  [void]$HostPanel.Controls.Add($pnlScroll)
  [void]$HostPanel.Controls.Add($script:lblNStatus)
  & $script:NoticeFitChrome

  # ---- helpers / handlers (same behavior as before) ----
  function Refresh-PresetCombos {
    $script:cboAppr.Items.Clear(); $script:cboRecv.Items.Clear()
    foreach ($a in @($script:Settings.ApprovalPresets)) { if ($a) { [void]$script:cboAppr.Items.Add([string]$a) } }
    foreach ($r in @($script:Settings.RecipientPresets)) { if ($r) { [void]$script:cboRecv.Items.Add([string]$r) } }
    if ($script:Settings.LastApprovalPreset) { $script:cboAppr.Text = [string]$script:Settings.LastApprovalPreset }
    elseif ($script:cboAppr.Items.Count -gt 0) { $script:cboAppr.SelectedIndex = 0 }
    if ($script:Settings.LastRecipientPreset) { $script:cboRecv.Text = [string]$script:Settings.LastRecipientPreset }
    elseif ($script:cboRecv.Items.Count -gt 0) { $script:cboRecv.SelectedIndex = 0 }
  }

  function Refresh-WxsCombos {
    $script:WxsCache = @(Get-WxsWindows)
    $script:cboNSrc.Items.Clear(); $script:cboNTmpl.Items.Clear()
    $srcIdx = -1; $tmplIdx = -1; $i = 0
    foreach ($w in $script:WxsCache) {
      [void]$script:cboNSrc.Items.Add($w.Display)
      [void]$script:cboNTmpl.Items.Add($w.Display)
      if ($srcIdx -lt 0 -and $w.Kind -eq 'received') { $srcIdx = $i }
      if ($tmplIdx -lt 0 -and $w.Kind -eq 'template') { $tmplIdx = $i }
      $i++
    }
    if ($srcIdx -ge 0) { $script:cboNSrc.SelectedIndex = $srcIdx }
    elseif ($script:cboNSrc.Items.Count -gt 0) { $script:cboNSrc.SelectedIndex = 0 }
    if ($tmplIdx -ge 0) { $script:cboNTmpl.SelectedIndex = $tmplIdx }
    elseif ($script:cboNTmpl.Items.Count -gt 0) { $script:cboNTmpl.SelectedIndex = 0 }
    $script:lblNStatus.Text = ('창 {0}개 감지 · {1}' -f @($script:WxsCache).Count, (Get-Date -Format 'HH:mm:ss'))
  }

  function Get-SelectedWxs {
    param($Combo)
    $i = $Combo.SelectedIndex
    if ($i -lt 0 -or $i -ge @($script:WxsCache).Count) { return $null }
    return $script:WxsCache[$i]
  }

  function Get-TemplateHwnd {
    $w = Get-SelectedWxs -Combo $script:cboNTmpl
    if ($null -ne $w) { return [IntPtr]$w.Hwnd }
    $cand = @($script:WxsCache | Where-Object { $_.Kind -eq 'template' } | Select-Object -First 1)
    if ($cand.Count -gt 0) { return [IntPtr]$cand[0].Hwnd }
    return [IntPtr]::Zero
  }

  function Invoke-NoticeReadSource {
    $w = Get-SelectedWxs -Combo $script:cboNSrc
    if ($null -eq $w) {
      [System.Windows.Forms.MessageBox]::Show('원문창을 선택하세요.', $script:AppName) | Out-Null
      return $false
    }
    $script:NoticeSourceTitle = $w.Title
    $body = Copy-TextFromHwpWindow -Hwnd ([IntPtr]$w.Hwnd)
    if ([string]::IsNullOrWhiteSpace($body)) {
      $clip = ''
      try { $clip = [System.Windows.Forms.Clipboard]::GetText() } catch { }
      if ($clip) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
          "HWP 복사가 비었습니다.`n클립보드를 원문으로 쓸까요?",
          $script:AppName, 'YesNo', 'Question')
        if ($ans -eq 'Yes') { $body = $clip }
      }
    }
    $script:NoticeSourceBody = $body
    $script:txtNotice.Text = ("[제목]`r`n{0}`r`n`r`n[본문]`r`n{1}" -f $script:NoticeSourceTitle, $script:NoticeSourceBody)
    $script:lblNStatus.Text = ('원문 읽음 · 본문 {0}자' -f $script:NoticeSourceBody.Length)
    return $true
  }

  function Invoke-NoticeLocalDraft {
    if (-not $script:NoticeSourceTitle -and -not $script:NoticeSourceBody) {
      [System.Windows.Forms.MessageBox]::Show('먼저 원문읽기.', $script:AppName) | Out-Null
      return $false
    }
    $att = Get-NoticeAttachmentNames -Hwnd ([IntPtr]::Zero) -BodyText ([string]$script:NoticeSourceBody)
    try {
      $wSrc = Get-SelectedWxs -Combo $script:cboNSrc
      if ($null -ne $wSrc) { $att = Get-NoticeAttachmentNames -Hwnd ([IntPtr]$wSrc.Hwnd) -BodyText ([string]$script:NoticeSourceBody) }
    } catch { }
    $script:LastAttachInfo = $att
    $script:NoticeDraft = New-SchoolNoticeDraft -Title $script:NoticeSourceTitle -Body $script:NoticeSourceBody -AttachmentNames @($att.Names)
    $script:txtNotice.Text = $script:NoticeDraft
    try { [System.Windows.Forms.Clipboard]::SetText($script:NoticeDraft) } catch { }
    $path = Join-Path $script:DraftDir (('{0}_local_notice.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($path, $script:NoticeDraft, $utf8bom)
    $script:lblNStatus.Text = '로컬 안내공문 초안 생성'
    return $true
  }

  function Invoke-NoticeFillTitle {
    $draft = $script:txtNotice.Text
    if (-not $draft) { $draft = $script:NoticeDraft }
    $title = $script:NoticeSourceTitle
    $m = [regex]::Match(($draft + ''), '^(?<t>[^\r\n]+)')
    if ($m.Success) {
      $cand = $m.Groups['t'].Value.Trim()
      if ($cand -and $cand -notmatch '^\[|^(제목|본문)') { $title = $cand }
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
      [System.Windows.Forms.MessageBox]::Show('제목 없음.', $script:AppName) | Out-Null
      return $false
    }
    $hwnd = Get-TemplateHwnd
    if ($hwnd -eq [IntPtr]::Zero) {
      [System.Windows.Forms.MessageBox]::Show('기안창 선택.', $script:AppName) | Out-Null
      return $false
    }
    $wait = Wait-ForWindowResponsive -Hwnd $hwnd -TimeoutMs 4000
    if (-not $wait.Ok) {
      $script:lblNStatus.Text = ('제목: 기안창 응답 없음({0}). 건드리지 않음' -f $wait.Reason)
      return $false
    }
    Invoke-ActivateWindow -Hwnd $hwnd | Out-Null
    $docTab = Find-NoticeDocInfoTabNode -Hwnd $hwnd
    if ($docTab) { Invoke-AccDefault -Node $docTab | Out-Null; Start-Sleep -Milliseconds 400 }
    $ie = Get-IeServerHwnd -Hwnd $hwnd
    $edit = Find-NoticeTitleEditNode -Hwnd $hwnd
    if ($null -eq $edit) {
      [System.Windows.Forms.Clipboard]::SetText($title)
      $script:lblNStatus.Text = '제목칸 못 찾음 · 클립보드에 복사'
      return $false
    }
    $ok = Set-AccEditValue -Node $edit -Text $title
    $script:lblNStatus.Text = ('제목 입력 ok={0}' -f $ok)
    if (-not $ok) { [System.Windows.Forms.Clipboard]::SetText($title) }
    return $ok
  }

  function Invoke-NoticeFillBody {
    $body = $script:txtNotice.Text
    if ([string]::IsNullOrWhiteSpace($body)) { $body = $script:NoticeDraft }
    if ([string]::IsNullOrWhiteSpace($body)) {
      [System.Windows.Forms.MessageBox]::Show('본문 없음.', $script:AppName) | Out-Null
      return $false
    }
    $lines = @($body -split "`r?`n")
    if ($lines.Count -gt 1 -and $lines[0] -match '안내\s*$') {
      $body = (($lines | Select-Object -Skip 1) -join "`r`n").TrimStart()
    }
    $hwnd = Get-TemplateHwnd
    if ($hwnd -eq [IntPtr]::Zero) {
      [System.Windows.Forms.MessageBox]::Show('기안창 선택.', $script:AppName) | Out-Null
      return $false
    }
    $wait = Wait-ForWindowResponsive -Hwnd $hwnd -TimeoutMs 8000
    if (-not $wait.Ok) {
      $script:lblNStatus.Text = ('본문: 기안창 응답 없음({0}). 건드리지 않음' -f $wait.Reason)
      [System.Windows.Forms.MessageBox]::Show(
        '기안창이 응답 없습니다. 풀린 뒤 다시 시도하세요. (기안창 미접촉)',
        $script:AppName) | Out-Null
      return $false
    }
    Invoke-ActivateWindow -Hwnd $hwnd | Out-Null
    $wait2 = Wait-ForWindowResponsive -Hwnd $hwnd -TimeoutMs 4000
    if (-not $wait2.Ok) {
      $script:lblNStatus.Text = ('본문: 활성화 후 응답 없음({0})' -f $wait2.Reason)
      return $false
    }
    $tabNode = Find-NoticeBodyTabNode -Hwnd $hwnd
    if ($tabNode) { Invoke-AccDefault -Node $tabNode | Out-Null; Start-Sleep -Milliseconds 500 }
    $hwp = Get-HwpBodyHwnd -Hwnd $hwnd
    if ($hwp -eq [IntPtr]::Zero) {
      [System.Windows.Forms.MessageBox]::Show('HwpMainEditWnd 없음.', $script:AppName) | Out-Null
      return $false
    }
    $cpl = 40; try { $cpl = [int]$script:Settings.CharsPerLine } catch { }; if ($cpl -lt 20) { $cpl = 40 }
    $spill = 5; try { $spill = [int]$script:Settings.SpillCharLimit } catch { }
    $maxT = 6; try { $maxT = [int]$script:Settings.MaxTightenSteps } catch { }
    $fillTitleRestore = ''
    $mTitle = [regex]::Match(($script:txtNotice.Text + ''), '^(?<t>[^\r\n]+)')
    if ($mTitle.Success) {
      $cand = $mTitle.Groups['t'].Value.Trim()
      if ($cand -and $cand -notmatch '^\[|^(제목|본문)') { $fillTitleRestore = $cand }
    }
    if (-not $fillTitleRestore) { $fillTitleRestore = [string]$script:NoticeSourceTitle }
    $fname = '굴림'; $fsize = 12
    try { if ($script:Settings.BodyFontName) { $fname = [string]$script:Settings.BodyFontName } } catch { }
    try { $fsize = [int]$script:Settings.BodyFontSize } catch { }
    $r = Format-PasteNoticeBodyToHwp -Hwnd $hwnd -Body $body -ClearFirst `
      -InTable:([bool]$script:chkInTable.Checked) `
      -TightenLetterSpacing:([bool]$script:chkTighten.Checked) `
      -CharsPerLine $cpl -SpillCharLimit $spill -MaxTightenSteps $maxT `
      -ApplyBodyFont:([bool]$script:chkFont.Checked) `
      -BodyFontName $fname -BodyFontSize $fsize `
      -TitleToRestore $fillTitleRestore
    $ok = $false; $steps = 0; $lc = 0; $fontOk = $false
    if ($r -is [bool]) { $ok = $r }
    elseif ($null -ne $r) {
      $ok = [bool]$r.Ok; $steps = [int]$r.TightenSteps; $lc = [int]$r.Lines
      try { $fontOk = [bool]$r.FontApplied } catch { }
    }
    if (-not $ok) {
      [System.Windows.Forms.Clipboard]::SetText($body)
      [System.Windows.Forms.MessageBox]::Show('자동 붙여넣기 실패. 본문탭에서 Ctrl+V.', $script:AppName) | Out-Null
    }
    $script:lblNStatus.Text = ('본문 입력 · 자간={0}({1}) · 글꼴={2} · 줄{3}' -f $script:chkTighten.Checked, $steps, $fontOk, $lc)
    return $ok
  }

  $btnNRefresh.add_Click({ try { Refresh-WxsCombos } catch { $script:lblNStatus.Text = $_.Exception.Message } })
  $btnNRead.add_Click({ try { [void](Invoke-NoticeReadSource) } catch { $script:lblNStatus.Text = '원문읽기 오류: ' + $_.Exception.Message } })
  $btnNLocal.add_Click({ try { [void](Invoke-NoticeLocalDraft) } catch { $script:lblNStatus.Text = '로컬초안 오류: ' + $_.Exception.Message } })
  $btnNTitle.add_Click({ try { [void](Invoke-NoticeFillTitle) } catch { $script:lblNStatus.Text = '제목 오류: ' + $_.Exception.Message } })
  $btnNBody.add_Click({ try { [void](Invoke-NoticeFillBody) } catch { $script:lblNStatus.Text = '본문 오류: ' + $_.Exception.Message } })

  # One-shot: read → draft → title → body
  $btnNOneShot.add_Click({
    try {
      if (-not (Invoke-NoticeReadSource)) { return }
      if (-not (Invoke-NoticeLocalDraft)) { return }
      $tOk = Invoke-NoticeFillTitle
      $bOk = Invoke-NoticeFillBody
      $script:lblNStatus.Text = ('안내공문 원샷 · 제목={0} 본문={1}' -f $tOk, $bOk)
    } catch {
      $script:lblNStatus.Text = '안내공문 원샷 오류: ' + $_.Exception.Message
    }
  })

  $btnNGrok.add_Click({
    try {
      if (-not $script:NoticeSourceBody -and -not $script:NoticeSourceTitle) {
        [System.Windows.Forms.MessageBox]::Show('먼저 원문읽기.', $script:AppName) | Out-Null
        return
      }
      $raw = ("제목: {0}`r`n`r`n{1}" -f $script:NoticeSourceTitle, $script:NoticeSourceBody)
      $masked = Mask-PersonalInfo -Text $raw
      $script:NoticeMasked = $masked.Masked
      $script:LastMaskPairs = @($masked.Pairs)
      $preview = New-Object System.Windows.Forms.Form
      $preview.Text = '마스킹 미리보기'
      $preview.Size = New-Object System.Drawing.Size(640, 520)
      $preview.StartPosition = 'CenterParent'
      $tb = New-Object System.Windows.Forms.TextBox
      $tb.Dock = 'Fill'; $tb.Multiline = $true; $tb.ScrollBars = 'Both'; $tb.ReadOnly = $true
      $tb.Text = $script:NoticeMasked
      $panel = New-Object System.Windows.Forms.FlowLayoutPanel
      $panel.Dock = 'Bottom'; $panel.Height = 40
      $ok = New-Object System.Windows.Forms.Button; $ok.Text = '복사·저장'; $ok.Width = 100
      $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = '취소'; $cancel.Width = 80
      $script:GrokPreviewOk = $false
      $ok.add_Click({ $script:GrokPreviewOk = $true; $preview.Close() })
      $cancel.add_Click({ $script:GrokPreviewOk = $false; $preview.Close() })
      [void]$panel.Controls.Add($ok); [void]$panel.Controls.Add($cancel)
      $preview.Controls.Add($tb); $preview.Controls.Add($panel)
      [void]$preview.ShowDialog()
      if (-not $script:GrokPreviewOk) { $script:lblNStatus.Text = '그록 다듬기 취소'; return }
      $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
      $header = [string]$script:Settings.GrokPromptHeader
      if (-not $header) { $header = '안내공문으로 바꿔줘' }
      $payload = "{0}`r`n`r`n{1}" -f $header, $script:NoticeMasked
      $outPath = Join-Path $script:OutboxDir ($stamp + '.txt')
      $utf8bom = New-Object System.Text.UTF8Encoding $true
      [System.IO.File]::WriteAllText($outPath, $payload, $utf8bom)
      [void](Save-MaskMapFile -Pairs $script:LastMaskPairs -Stamp $stamp)
      [System.Windows.Forms.Clipboard]::SetText($payload)
      $script:txtNotice.Text = $payload
      $script:lblNStatus.Text = ("outbox·클립보드 · 마스크 {0}건" -f @($script:LastMaskPairs).Count)
    } catch {
      $script:lblNStatus.Text = '그록 다듬기 오류: ' + $_.Exception.Message
    }
  })

  $btnNGrokPaste.add_Click({
    try {
      $clip = ''; try { $clip = [System.Windows.Forms.Clipboard]::GetText() } catch { }
      if ([string]::IsNullOrWhiteSpace($clip)) {
        [System.Windows.Forms.MessageBox]::Show('클립보드 비어 있음.', $script:AppName) | Out-Null
        return
      }
      $pairs = $script:LastMaskPairs
      if (-not $pairs -or $pairs.Count -eq 0) {
        $latest = Get-ChildItem -LiteralPath $script:MaskMapDir -Filter '*.json' -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
          $obj = Read-JsonFile -Path $latest.FullName -Default $null
          if ($obj -and $obj.Pairs) { $pairs = @($obj.Pairs); $script:LastMaskPairs = $pairs }
        }
      }
      $restored = Unmask-PersonalInfo -Text $clip -Pairs $pairs
      $restored = [regex]::Replace($restored, '^안내공문으로 바꿔줘\s*', '')
      $script:NoticeDraft = $restored.Trim() + "`r`n"
      $script:txtNotice.Text = $script:NoticeDraft
      $script:lblNStatus.Text = ('그록 결과 복원 · {0}자' -f $script:NoticeDraft.Length)
    } catch {
      $script:lblNStatus.Text = '그록 결과 오류: ' + $_.Exception.Message
    }
  })

  $btnNAppr.add_Click({
    try {
      $name = $script:cboAppr.Text.Trim()
      $hwnd = Get-TemplateHwnd
      if ($hwnd -eq [IntPtr]::Zero) {
        [System.Windows.Forms.MessageBox]::Show('기안창 선택.', $script:AppName) | Out-Null
        return
      }
      Invoke-ActivateWindow -Hwnd $hwnd | Out-Null
      $acc = Get-IeAccFromHwnd -Hwnd $hwnd
      $nodes = @(Find-AccNodes -Root $acc -NameLike '결재경로(새창열기)' -MinW 20)
      if ($nodes.Count -eq 0) { $nodes = @(Find-AccNodes -Root $acc -NameLike '*결재경로*' -MinW 20) }
      $btn = $nodes | Where-Object { $_.Name -like '*새창*' -or $_.Action -eq '점프' } | Select-Object -First 1
      if ($null -eq $btn) { $btn = $nodes | Select-Object -First 1 }
      if ($null -eq $btn) {
        [System.Windows.Forms.MessageBox]::Show('결재경로 버튼 없음.', $script:AppName) | Out-Null
        return
      }
      Invoke-AccDefault -Node $btn | Out-Null
      Start-Sleep -Milliseconds 800
      if ($name) {
        [System.Windows.Forms.Clipboard]::SetText($name)
        $script:Settings.LastApprovalPreset = $name
        Save-PenSettings -Settings $script:Settings
        $script:lblNStatus.Text = ("결재경로 열림 · '{0}' 클립보드 (결재올림 금지)" -f $name)
      } else {
        $script:lblNStatus.Text = '결재경로 열림 (결재올림 금지)'
      }
    } catch {
      $script:lblNStatus.Text = '결재선 오류: ' + $_.Exception.Message
    }
  })

  $btnNRecv.add_Click({
    try {
      $name = $script:cboRecv.Text.Trim()
      $hwnd = Get-TemplateHwnd
      if ($hwnd -eq [IntPtr]::Zero) {
        [System.Windows.Forms.MessageBox]::Show('기안창 선택.', $script:AppName) | Out-Null
        return
      }
      Invoke-ActivateWindow -Hwnd $hwnd | Out-Null
      $acc = Get-IeAccFromHwnd -Hwnd $hwnd
      $nodes = @(Find-AccNodes -Root $acc -NameLike '수신자지정(새창열기)' -MinW 10)
      if ($nodes.Count -eq 0) { $nodes = @(Find-AccNodes -Root $acc -NameLike '*수신자*' -MinW 10) }
      $btn = $nodes | Where-Object { $_.Name -like '*지정*' -or $_.Name -like '*새창*' } | Select-Object -First 1
      if ($null -eq $btn) { $btn = $nodes | Select-Object -First 1 }
      if ($null -eq $btn) {
        [System.Windows.Forms.MessageBox]::Show('수신자지정 버튼 없음.', $script:AppName) | Out-Null
        return
      }
      Invoke-AccDefault -Node $btn | Out-Null
      if ($name) {
        [System.Windows.Forms.Clipboard]::SetText($name)
        $script:Settings.LastRecipientPreset = $name
        Save-PenSettings -Settings $script:Settings
      }
      $script:lblNStatus.Text = '수신자 창 열림 (발송/결재올림 금지)'
    } catch {
      $script:lblNStatus.Text = '수신처 오류: ' + $_.Exception.Message
    }
  })

  $btnNPresetSave.add_Click({
    $ap = $script:cboAppr.Text.Trim()
    $rc = $script:cboRecv.Text.Trim()
    $aps = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($script:Settings.ApprovalPresets)) { if ($x) { [void]$aps.Add([string]$x) } }
    $rcs = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($script:Settings.RecipientPresets)) { if ($x) { [void]$rcs.Add([string]$x) } }
    if ($ap -and ($aps -notcontains $ap)) { [void]$aps.Add($ap) }
    if ($rc -and ($rcs -notcontains $rc)) { [void]$rcs.Add($rc) }
    $script:Settings.ApprovalPresets = @($aps)
    $script:Settings.RecipientPresets = @($rcs)
    $script:Settings.LastApprovalPreset = $ap
    $script:Settings.LastRecipientPreset = $rc
    Save-PenSettings -Settings $script:Settings
    Refresh-PresetCombos
    $script:lblNStatus.Text = '프리셋 저장'
  })

  $btnNSync.add_Click({
    try {
      $hwnd = Get-TemplateHwnd
      if ($hwnd -eq [IntPtr]::Zero) {
        [System.Windows.Forms.MessageBox]::Show('기안창 선택.', $script:AppName) | Out-Null
        return
      }
      Invoke-ActivateWindow -Hwnd $hwnd | Out-Null
      $acc = Get-IeAccFromHwnd -Hwnd $hwnd
      $btn = @(Find-AccNodes -Root $acc -NameLike '결재경로(새창열기)' -MinW 20) | Select-Object -First 1
      if ($btn) { Invoke-AccDefault -Node $btn | Out-Null; Start-Sleep -Milliseconds 900 }
      $imported = New-Object System.Collections.Generic.List[string]
      $root = [System.Windows.Automation.AutomationElement]::RootElement
      $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
      foreach ($w in $wins) {
        try {
          $t = [string]$w.Current.Name
          if ($t -notmatch '결재|경로') { continue }
          $h = [IntPtr]$w.Current.NativeWindowHandle
          $a2 = Get-IeAccFromHwnd -Hwnd $h
          if ($null -eq $a2) { try { $a2 = [PenNoticeNative]::GetAcc($h) } catch { } }
          if ($null -eq $a2) { continue }
          foreach ($n in @(Find-AccNodes -Root $a2 -NameLike '*' -MinW 20 -MaxNodes 500)) {
            $nm = [string]$n.Name
            if ([string]::IsNullOrWhiteSpace($nm)) { continue }
            if ($nm.Length -lt 2 -or $nm.Length -gt 40) { continue }
            if ($nm -match '결재|경로|닫기|확인|취소|저장|버튼|목록|검색|새창|지정|순번') { continue }
            if ($nm -match '[가-힣]') { [void]$imported.Add($nm) }
          }
        } catch { }
      }
      $uniq = @($imported | Select-Object -Unique)
      if (@($uniq).Count -eq 0) {
        $script:lblNStatus.Text = '동기화 실패 — 수동 입력'
        return
      }
      $aps = New-Object System.Collections.Generic.List[string]
      foreach ($x in @($script:Settings.ApprovalPresets)) { if ($x) { [void]$aps.Add([string]$x) } }
      foreach ($u in $uniq) { if ($aps -notcontains $u) { [void]$aps.Add($u) } }
      $script:Settings.ApprovalPresets = @($aps)
      Save-PenSettings -Settings $script:Settings
      Refresh-PresetCombos
      $script:lblNStatus.Text = ('동기화 후보 {0}개' -f @($uniq).Count)
    } catch {
      $script:lblNStatus.Text = '동기화 오류: ' + $_.Exception.Message
    }
  })

  $btnNAttachSave.add_Click({
    try {
      $srcHwnd = [IntPtr]::Zero
      try {
        $wSrc = Get-SelectedWxs -Combo $script:cboNSrc
        if ($null -ne $wSrc) { $srcHwnd = [IntPtr]$wSrc.Hwnd }
      } catch { }
      $body = ''; try { $body = [string]$script:txtNotice.Text } catch { }
      if (-not $body) { try { $body = [string]$script:NoticeSourceBody } catch { } }
      if ((-not $body) -and $srcHwnd -ne [IntPtr]::Zero) {
        try { $body = Copy-TextFromHwpWindow -Hwnd $srcHwnd } catch { }
      }
      $info = Get-NoticeAttachmentNames -Hwnd $srcHwnd -BodyText $body
      $script:LastAttachInfo = $info
      $save = Save-NoticeAttachmentsLocal -Hwnd $srcHwnd -Names @($info.Names)
      $script:LastAttachSave = $save
      try {
        if ($script:txtNotice -and $script:txtNotice.Text) {
          $t = [string]$script:txtNotice.Text
          if ($t -match '(?s)^(.*?)(\r?\n)\s*붙임\b[\s\S]*$') {
            $head = $Matches[1].TrimEnd()
            $script:txtNotice.Text = ($head + "`r`n`r`n" + $info.Ending + "`r`n")
          } elseif ($info.Ending) {
            $script:txtNotice.Text = ($t.TrimEnd() + "`r`n`r`n" + $info.Ending + "`r`n")
          }
        }
      } catch { }
      $script:lblNStatus.Text = ("붙임 {0}개 · {1}" -f $info.Count, $save.Dir)
    } catch {
      $script:lblNStatus.Text = '붙임 처리 오류: ' + $_.Exception.Message
    }
  })

  $btnNAttachPut.add_Click({
    try {
      $tmplHwnd = [IntPtr]::Zero
      try { $tmplHwnd = Get-TemplateHwnd } catch { }
      $files = @()
      if ($script:LastAttachSave -and $script:LastAttachSave.SavedPaths) {
        $files = @($script:LastAttachSave.SavedPaths)
      }
      if ((@($files).Count -eq 0) -and $script:LastAttachSave -and $script:LastAttachSave.Dir) {
        $files = @(Get-ChildItem -LiteralPath $script:LastAttachSave.Dir -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notlike '*.url.txt' -and $_.Extension -ne '.txt' } |
          ForEach-Object { $_.FullName })
      }
      $r = Invoke-NoticeAttachFilesToDraft -DraftHwnd $tmplHwnd -FilePaths $files -DryRun
      $script:lblNStatus.Text = '첨부넣기: 드라이런 — ' + $r.Message
    } catch {
      $script:lblNStatus.Text = '첨부넣기 오류: ' + $_.Exception.Message
    }
  })

  try { Import-TripFieldDiscovery | Out-Null } catch { }
  Refresh-PresetCombos
  Refresh-WxsCombos
}

function Add-TripPage {
  param($HostPanel)
  if (-not (Get-Variable -Name MoreGridMap -Scope Script -ErrorAction SilentlyContinue)) { $script:MoreGridMap = @{} }
  $tt = New-Object System.Windows.Forms.ToolTip
  $cTeal = '#30B0C7'

  $script:lblTripStatus = New-Object System.Windows.Forms.Label
  $script:lblTripStatus.Dock = 'Bottom'
  $script:lblTripStatus.Height = 28
  $script:lblTripStatus.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
  $script:lblTripStatus.Text = '출장신청: 원문에서 추출하거나 직접 입력 후 포털 양식 채우기'
  $script:lblTripStatus.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7')
  $script:lblTripStatus.Font = New-Object System.Drawing.Font('맑은 고딕', 9)

  $scroll = New-Object System.Windows.Forms.Panel
  $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true
  $scroll.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7')
  $scroll.Tag = 'bg'; $scroll.Padding = New-Object System.Windows.Forms.Padding(16)

  function New-TripCard([string]$Title) {
    $card = New-Object System.Windows.Forms.Panel
    $card.AutoSize = $false
    $card.Padding = New-Object System.Windows.Forms.Padding(16)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
    $card.BackColor = [System.Drawing.Color]::White; $card.Tag = 'card'
    $card.add_Paint({
      param($s, $e)
      $pen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')), 1
      $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1)
      $pen.Dispose()
    })
    $inner = New-Object System.Windows.Forms.FlowLayoutPanel
    $inner.FlowDirection = 'TopDown'; $inner.WrapContents = $false; $inner.AutoSize = $true
    $inner.BackColor = [System.Drawing.Color]::White; $inner.Tag = 'card'
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $Title; $h.AutoSize = $true
    $h.Font = New-Object System.Drawing.Font('맑은 고딕', 13, [System.Drawing.FontStyle]::Bold)
    $h.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
    $h.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    [void]$inner.Controls.Add($h)
    [void]$card.Controls.Add($inner)
    return @{ Card = $card; Inner = $inner }
  }

  function New-TripTile([string]$Text, [string]$Emoji, [string]$Hex, [switch]$Sec, [switch]$Accent, [string]$DotHex = '', [string]$Tip = '') {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ("{0}`r`n{1}" -f $Emoji, $Text)
    $b.Size = New-Object System.Drawing.Size(110, 80)
    $b.Margin = New-Object System.Windows.Forms.Padding(4)
    $b.FlatStyle = 'Flat'; $b.Font = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand; $b.UseVisualStyleBackColor = $false
    $b.TextAlign = 'MiddleCenter'
    if ($Accent) {
      $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
      $b.ForeColor = [System.Drawing.Color]::White
      $b.FlatAppearance.BorderSize = 0
      $b.Tag = 'uicolor:#007AFF;tile;radius12'
    } elseif ($Sec) {
      $b.BackColor = [System.Drawing.Color]::White
      $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
      $b.FlatAppearance.BorderSize = 1
      $b.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
      $b.Tag = 'uicolor:#FFFFFF;outline;tile;radius12'
    } else {
      $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#E5E5EA')
      $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
      $b.FlatAppearance.BorderSize = 0
      $b.Tag = 'uicolor:#E5E5EA;tile;radius12'
    }
    if ($DotHex) {
      $b.Name = ('dot:{0}' -f $DotHex)
      $b.Text = $Text
      $b.add_Paint({
        param($s, $e)
        if ([string]$s.Name -like 'dot:*') {
          $col = [System.Drawing.ColorTranslator]::FromHtml(([string]$s.Name).Substring(4))
          $brush = New-Object System.Drawing.SolidBrush $col
          $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
          $e.Graphics.FillEllipse($brush, 10, 10, 10, 10)
          $brush.Dispose()
        }
      })
    }
    if ($Tip) { $tt.SetToolTip($b, $Tip) }
    if (Get-Command Set-RoundedRegion -ErrorAction SilentlyContinue) {
      Set-RoundedRegion -Control $b -Radius 12
      $b.add_Resize({ Set-RoundedRegion -Control $this -Radius 12 })
    }
    return $b
  }

  $c1 = New-TripCard '출장신청'
  $g1 = New-Object System.Windows.Forms.FlowLayoutPanel
  $g1.AutoSize = $true; $g1.AutoSizeMode = 'GrowAndShrink'; $g1.WrapContents = $true; $g1.BackColor = [System.Drawing.Color]::White; $g1.Tag = 'tilegrid'
  $btnTripExtract = New-TripTile '원문추출' '▣' '#E5E5EA' -DotHex $cTeal -Tip '안내공문 원문/미리보기에서 출장 정보를 추출합니다'
  $btnTripOneShot = New-TripTile '출장신청' '▲' '#007AFF' -Accent -Tip '추출→검토값으로 포털 양식 채우기 (신청/상신 금지)'
  $btnTripFill = New-TripTile '양식채우기' '✎' '#E5E5EA' -Sec -Tip '아래 검토 필드로 포털 양식만 채웁니다 (신청 금지)'
  $btnTripOpen = New-TripTile '포털열기' '◆' '#E5E5EA' -Sec -Tip '출장 포털만 엽니다 (입력 없음)'
  $btnTripCopy = New-TripTile '값복사' '▤' '#E5E5EA' -Sec -Tip '검토 필드를 클립보드에 복사'
  foreach ($b in @($btnTripOneShot, $btnTripExtract)) { [void]$g1.Controls.Add($b) }
  $btnTripMore = New-Object System.Windows.Forms.Button
  $btnTripMore.Text = '▾ 더보기'
  $btnTripMore.AutoSize = $true
  $btnTripMore.FlatStyle = 'Flat'
  $btnTripMore.FlatAppearance.BorderSize = 0
  $btnTripMore.BackColor = [System.Drawing.Color]::White
  $btnTripMore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#6E6E73')
  $btnTripMore.Font = New-Object System.Drawing.Font('맑은 고딕', 10, [System.Drawing.FontStyle]::Bold)
  $btnTripMore.Cursor = [System.Windows.Forms.Cursors]::Hand
  $btnTripMore.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 4)
  $btnTripMore.Tag = 'morelink'
  $gTripMore = New-Object System.Windows.Forms.FlowLayoutPanel
  $gTripMore.AutoSize = $true
  $gTripMore.AutoSizeMode = 'GrowAndShrink'
  $gTripMore.WrapContents = $true
  $gTripMore.BackColor = [System.Drawing.Color]::White
  $gTripMore.Tag = 'tilegrid'
  $gTripMore.Visible = $false
  foreach ($b in @($btnTripFill, $btnTripOpen, $btnTripCopy)) { [void]$gTripMore.Controls.Add($b) }
  $btnTripMore.Name = 'more_trip'
  $script:MoreGridMap['more_trip'] = $gTripMore
  $btnTripMore.add_Click({
    param($s,$e)
    $grid = $script:MoreGridMap[$s.Name]
    if ($null -eq $grid) { return }
    $grid.Visible = -not $grid.Visible
    $s.Text = if ($grid.Visible) { '▴ 접기' } else { '▾ 더보기' }
    if ($script:TripFitChrome) { & $script:TripFitChrome }
  })
  [void]$c1.Inner.Controls.Add($g1)
  [void]$c1.Inner.Controls.Add($btnTripMore)
  [void]$c1.Inner.Controls.Add($gTripMore)

  $c2 = New-TripCard '검토 필드'
  function Add-Field([string]$Label, [int]$Width = 420) {
    $wrap = New-Object System.Windows.Forms.FlowLayoutPanel
    $wrap.FlowDirection = 'TopDown'; $wrap.AutoSize = $true; $wrap.WrapContents = $false
    $wrap.BackColor = [System.Drawing.Color]::White; $wrap.Tag = 'fullrow'
    $wrap.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Label; $l.AutoSize = $true
    $l.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
    $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F')
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Width = $Width; $t.Font = New-Object System.Drawing.Font('맑은 고딕', 11)
    $t.Tag = 'fulltext'
    [void]$wrap.Controls.Add($l); [void]$wrap.Controls.Add($t)
    return @{ Wrap = $wrap; Box = $t }
  }
  $fReason = Add-Field '사유'
  $fStart = Add-Field '시작일시' 200
  $fEnd = Add-Field '종료일시' 200
  $fPlace = Add-Field '출장지'
  $fRegion = Add-Field '관내/관외 (부산→관내 자동)' 200
  $script:txtTripReason = $fReason.Box
  $script:txtTripStart = $fStart.Box
  $script:txtTripEnd = $fEnd.Box
  $script:txtTripPlace = $fPlace.Box
  $script:txtTripRegion = $fRegion.Box
  $script:txtTripPlace.add_TextChanged({
    $p = [string]$script:txtTripPlace.Text
    if ($p -match '부산') { $script:txtTripRegion.Text = '관내' }
    elseif ($p -and -not $script:txtTripRegion.Text) { $script:txtTripRegion.Text = '관외' }
  })
  foreach ($f in @($fReason, $fStart, $fEnd, $fPlace, $fRegion)) { [void]$c2.Inner.Controls.Add($f.Wrap) }

  $script:TripChromeCards = @($c1.Card, $c2.Card)
  $script:TripScrollHost = $scroll
  for ($i = $script:TripChromeCards.Count - 1; $i -ge 0; $i--) {
    $card = $script:TripChromeCards[$i]
    $card.Dock = 'Top'
    $card.AutoSize = $false
    $card.Region = $null
    $card.Height = 200
    [void]$scroll.Controls.Add($card)
  }
  function script:Stretch-TripTree {
    param($Root, [int]$InnerW)
    if ($null -eq $Root) { return }
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
      $n = $queue.Dequeue()
      foreach ($ch in @($n.Controls)) { $queue.Enqueue($ch) }
      $tag = [string]$n.Tag
      if ($n -is [System.Windows.Forms.FlowLayoutPanel]) {
        $n.Width = $InnerW
        $n.MaximumSize = New-Object System.Drawing.Size($InnerW, 100000)
        if ($n.Dock -ne 'Top') { $n.Dock = 'Top' }
      }
      if ($n -is [System.Windows.Forms.TextBox] -and $tag -eq 'fulltext') {
        $n.Width = [Math]::Max(200, $InnerW - 8)
      }
    }
  }
  $fitTrip = {
    try {
      $hostW = $script:TripScrollHost.ClientSize.Width
      if ($hostW -le 40) { return }
      $innerW = [Math]::Max(300, $hostW - 40)
      $script:TripScrollHost.SuspendLayout()
      foreach ($c in @($script:TripChromeCards)) {
        if ($null -eq $c) { continue }
        $c.SuspendLayout()
        $c.Dock = 'Top'
        $c.AutoSize = $false
        $c.Region = $null
        $c.Width = $hostW
        script:Stretch-TripTree -Root $c -InnerW $innerW
        $inner = $null
        foreach ($ch in @($c.Controls)) {
          if ($ch -is [System.Windows.Forms.FlowLayoutPanel]) { $inner = $ch; break }
        }
        if ($null -ne $inner) {
          $inner.Width = $innerW
          $pref = $inner.GetPreferredSize((New-Object System.Drawing.Size($innerW, 0)))
          $c.Height = [Math]::Max(120, $pref.Height + $c.Padding.Top + $c.Padding.Bottom + 12)
        }
        $c.ResumeLayout($true)
      }
      $script:TripScrollHost.ResumeLayout($true)
    } catch {
      try { $script:lblTripStatus.Text = ('레이아웃: ' + $_.Exception.Message) } catch { }
    }
  }
  $script:TripFitChrome = $fitTrip
  $scroll.add_Resize({ if ($script:TripFitChrome) { & $script:TripFitChrome } })
  $HostPanel.add_Resize({ if ($script:TripFitChrome) { & $script:TripFitChrome } })
  [void]$HostPanel.Controls.Add($scroll)
  [void]$HostPanel.Controls.Add($script:lblTripStatus)
  & $script:TripFitChrome

  function Get-TripFieldsDraft {
    $date = [string]$script:txtTripStart.Text
    $time = ''
    # split date/time if combined in start; end holds end
    return [pscustomobject]@{
      Reason = [string]$script:txtTripReason.Text
      Region = [string]$script:txtTripRegion.Text
      Date = $date
      Time = ([string]$script:txtTripStart.Text + ' ~ ' + [string]$script:txtTripEnd.Text)
      Place = [string]$script:txtTripPlace.Text
      PortalUrl = $(if ($script:TripPortalUrl) { [string]$script:TripPortalUrl } else { '' })
      CopyText = @(
        ('출장사유: {0}' -f $script:txtTripReason.Text),
        ('구분: {0}' -f $script:txtTripRegion.Text),
        ('시작: {0}' -f $script:txtTripStart.Text),
        ('종료: {0}' -f $script:txtTripEnd.Text),
        ('장소: {0}' -f $script:txtTripPlace.Text)
      ) -join "`r`n"
    }
  }

  function Apply-TripDraftToFields($Draft) {
    $script:txtTripReason.Text = [string]$Draft.Reason
    $script:txtTripPlace.Text = [string]$Draft.Place
    $script:txtTripRegion.Text = [string]$Draft.Region
    $start = [string]$Draft.Date
    if ($Draft.Time) { $start = ($start + ' ' + $Draft.Time).Trim() }
    $script:txtTripStart.Text = $start
    $script:txtTripEnd.Text = ''
    if ($Draft.Place -match '부산') { $script:txtTripRegion.Text = '관내' }
  }

  function Invoke-TripExtractFromNotice {
    $title = [string]$script:NoticeSourceTitle
    $body = [string]$script:NoticeSourceBody
    if (-not $title -and $script:txtNotice) {
      $raw = [string]$script:txtNotice.Text
      if ($raw -match '(?s)\[제목\]\s*(.+?)\s*\[본문\]\s*(.*)$') {
        $title = $Matches[1].Trim(); $body = $Matches[2].Trim()
      } elseif ($raw) { $title = ($raw -split "`r?`n")[0] }
    }
    if (-not $title -and -not $body) {
      [System.Windows.Forms.MessageBox]::Show('안내공문에서 원문읽기를 먼저 하세요.', $script:AppName) | Out-Null
      return $null
    }
    $draft = Get-TripDraftFromNotice -Title $title -Body $body
    if ($script:TripPortalUrl) { $draft.PortalUrl = [string]$script:TripPortalUrl }
    Apply-TripDraftToFields $draft
    $script:LastTripDraft = $draft
    $script:lblTripStatus.Text = '원문에서 출장 정보 추출 완료'
    return $draft
  }

  $btnTripExtract.add_Click({ try { [void](Invoke-TripExtractFromNotice) } catch { $script:lblTripStatus.Text = $_.Exception.Message } })
  $btnTripCopy.add_Click({
    try {
      $d = Get-TripFieldsDraft
      [System.Windows.Forms.Clipboard]::SetText($d.CopyText)
      $script:lblTripStatus.Text = '출장 값 클립보드 복사됨'
    } catch { $script:lblTripStatus.Text = $_.Exception.Message }
  })
  $btnTripOpen.add_Click({
    try {
      $d = Get-TripFieldsDraft
      $url = [string]$d.PortalUrl
      if (-not $url) { $url = [string]$script:TripPortalUrl }
      if (-not $url) { $url = $script:Urls['업무포털'] }
      if (Get-Command Open-InChrome -ErrorAction SilentlyContinue) { Open-InChrome -Url $url }
      else { Start-Process $url }
      $script:lblTripStatus.Text = '포털 열기(입력 없음)'
    } catch { $script:lblTripStatus.Text = $_.Exception.Message }
  })
  $btnTripFill.add_Click({
    try {
      $d = Get-TripFieldsDraft
      $fill = Invoke-TripFormFill -Draft $d
      $script:lblTripStatus.Text = '포털 양식 채우기: ' + $fill.Message
    } catch { $script:lblTripStatus.Text = $_.Exception.Message }
  })
  $btnTripOneShot.add_Click({
    try {
      $draft = Invoke-TripExtractFromNotice
      if ($null -eq $draft) { return }
      $d = Get-TripFieldsDraft
      $fill = Invoke-TripFormFill -Draft $d
      $script:lblTripStatus.Text = '출장신청 원샷: ' + $fill.Message
    } catch { $script:lblTripStatus.Text = $_.Exception.Message }
  })

  try { Import-TripFieldDiscovery | Out-Null } catch { }
}

# Compat: old name still works if someone passes Tabs
function Add-NoticeTab {
  param($Tabs)
  # no-op compatibility — main shell uses Add-NoticePage
  Write-Host 'Add-NoticeTab skipped (sidebar shell uses Add-NoticePage)'
}
