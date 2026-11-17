# Apple Human Interface Guidelines — notes for PEN Helper (WinForms)

Sources (fetched 2026-11-01):
- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/design/human-interface-guidelines/dark-mode
- https://developer.apple.com/design/human-interface-guidelines/typography
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/design/human-interface-guidelines/materials
- UIKit system color tables (UIColor light/dark hex)

## Color — system / semantic (exact hex)

### Tint (system colors)

| Token | Light | Dark |
|-------|-------|------|
| systemBlue | #007AFF | #0A84FF |
| systemGreen | #34C759 | #30D158 |
| systemRed | #FF3B30 | #FF453A |
| systemOrange | #FF9500 | #FF9F0A |
| systemPink | #FF2D55 | #FF375F |
| systemPurple | #AF52DE | #BF5AF2 |
| systemTeal | #30B0C7 | #40C8E0 |
| systemCyan | #32ADE6 | #64D2FF |
| systemIndigo | #5856D6 | #5E5CE6 |
| systemYellow | #FFCC00 | #FFD60A |
| systemGray | #8E8E93 | #8E8E93 |
| systemGray2 | #AEAEB2 | #636366 |
| systemGray3 | #C7C7CC | #48484A |
| systemGray4 | #D1D1D6 | #3A3A3C |
| systemGray5 | #E5E5EA | #2C2C2E |
| systemGray6 | #F2F2F7 | #1C1C1E |

### Labels

| Token | Light | Dark |
|-------|-------|------|
| label | #000000 | #FFFFFF |
| secondaryLabel | #3C3C43 @ 60% ≈ #8E8E93 solid | #EBEBF5 @ 60% ≈ #98989D solid |
| tertiaryLabel | #3C3C43 @ 30% | #EBEBF5 @ 30% |
| placeholderText | #3C3C43 @ 30% | #EBEBF5 @ 30% |
| link | #007AFF | #0984FF |

### Backgrounds / fills / separators

| Token | Light | Dark |
|-------|-------|------|
| systemBackground | #FFFFFF | #000000 |
| secondarySystemBackground | #F2F2F7 | #1C1C1E |
| tertiarySystemBackground | #FFFFFF | #2C2C2E |
| systemGroupedBackground | #F2F2F7 | #000000 |
| secondarySystemGroupedBackground | #FFFFFF | #1C1C1E |
| opaqueSeparator | #C6C6C8 | #38383A |

### Dark Mode rules
- Prefer semantic roles (background / label / tint), not fixed RGB.
- Raise fill elevation in dark: black → gray6 → gray5.
- Tint colors brighten slightly in dark for contrast on black.
- Separators become lighter relative to dark surfaces (#38383A).

## Typography (iOS Large / default)

| Style | Size | Weight | Leading |
|-------|------|--------|---------|
| Large Title | 34pt | Regular / Bold emp. | 41 |
| Title 1 | 28pt | Regular | 34 |
| Title 2 | 22pt | Regular | 28 |
| Title 3 | 20pt | Regular / Semibold emp. | 25 |
| Headline | 17pt | **Semibold** | 22 |
| Body | 17pt | Regular / Semibold emp. | 22 |
| Callout | 16pt | Regular | 21 |
| Subheadline | 15pt | Regular | 20 |
| Footnote | 13pt | Regular | 18 |
| Caption 1 | 12pt | Regular | 16 |
| Caption 2 | 11pt | Regular | 13 |

macOS default body ≈ 13pt. Font family: SF Pro (Text ≤19, Display ≥20).
WinForms stand-in: 맑은 고딕 — map Semibold → Bold.

### PEN Helper mapped scale (desktop, strong readability)
| Role | Size | Style |
|------|------|-------|
| Title / stephead | 15pt | Bold |
| Body / UI | 12pt | Regular |
| Button | 11pt | Bold |
| Section label | 10pt | Bold |
| Caption / status | 9pt | Regular |
| Brand | 13pt | Bold |

## Layout & spacing
- Base unit **8pt**; common steps 4 / 8 / 16 / 20.
- Standard layout margins 16–20pt; for dense desktop tools use **8pt** outer, **4–8pt** inner.
- Minimum tap/hit target **44×44 pt** (desktop mouse can go slightly tighter; keep ≥36px height).
- Button centers ≥ ~60pt apart when stacked for eye/pointer comfort.
- Prefer full-width cards in content column; avoid large empty gutters.
- Lists: compact row padding (8h / 6v), 4–8 gap between rows.

## Corner radius (continuous / squircle intent)
| Element | Radius |
|---------|--------|
| Compact control / text field | 8pt |
| Theme pill / small chip | 10pt |
| Tile / nav selected | 12pt |
| Card / sheet | 10–12pt (WinForms: border paint; avoid Region clip on cards) |
| Large modal / prominent card | 16–20pt |

## Buttons
- Styles: filled (accent + white label), tinted/soft (tile fill + label), gray, plain, outline.
- Hit region ≥ 44×44; primary actions use system tint (blue / theme accent).
- Destructive: systemRed; cancel/secondary: outline or muted fill.
- Enough padding around control so it reads as tappable; flat style with hover/pressed states.

## Materials
- System materials: ultraThin / thin / regular / thick / chrome — blur + vibrancy over content.
- WinForms cannot do true vibrancy; approximate with solid semantic backgrounds:
  - Sidebar / chrome → secondarySystemBackground / gray6
  - Cards → secondaryGrouped / white (light) or gray6 (dark)
  - Status bar → same as chrome, muted label text
- Prefer opaque semantic fills over fake translucency on GDI+.

## Theme mapping (PEN)

| Theme | Mode | Bg | Card | Tile | Accent | Text | Muted | Border |
|-------|------|----|------|------|--------|------|-------|--------|
| black | Dark | #000000 | #1C1C1E | #2C2C2E | #0A84FF | #FFFFFF | #98989D | #38383A |
| sky | Light tint | #EAF4FF | #FFFFFF | #D6EBFF | #007AFF | #000000 | #5A6A7A | #B8D4F0 |
| pink | Light tint | #FFF0F5 | #FFFFFF | #FFE4EC | #FF2D55 | #000000 | #8E6A75 | #FFD0DC |
| white | Light | #F2F2F7 | #FFFFFF | #E5E5EA | #007AFF | #000000 | #8E8E93 | #C6C6C8 |

Danger/Success always HIG systemRed/systemGreen for active mode.
