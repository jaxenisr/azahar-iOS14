# Design

The app is being moved from a dark, all-purpose look to the era just before
Liquid Glass: a near-white page, white cards with real depth, hairlines, one
accent, and motion that feels physical. This file records the rules, the
components and the two layouts. It is the reference for every phase.

## Tokens

All of them live in `App/Sources/Design/Theme.swift` under `Design`. A screen that
needs a value not in this table is a screen with a hierarchy problem.

| Token | Value | Used for |
|---|---|---|
| `Palette.background` | `#F5F5F7` | the page |
| `Palette.card` | `#FFFFFF` | cards, rows, circular buttons |
| `Palette.ink` | `#111114` | primary text |
| `Palette.secondaryInk` | `#8A8A8E` | subtitles, metadata |
| `Palette.hairline` | `#E6E6EA` | separators, outlines |
| `Palette.accent` | `#7B6CF6` | selection, active pill, links |
| `Palette.positive` | `#34C759` | confirm buttons only |
| `Palette.playerBackground` | `#000000` | the player, always dark |
| `Radius.cover` / `Radius.card` | 20 / 24 | artwork / cards |
| `Elevation.card` | y 2, blur 12, black 6% | cards |
| `Elevation.cover` | y 1, blur 4, black 8% | artwork, circular buttons |
| `Fonts.title` | 34 bold | screen title |
| `Fonts.section` | 20 bold | card header |
| `Fonts.rowTitle` | 17 semibold | row label |
| `Fonts.rowSubtitle` | 15 regular | row explanation |
| `Fonts.cellName` / `cellMeta` | 17 semibold / 15 regular | library cell |
| `Fonts.caption` | 13 | the smallest text |
| `Space.xxs…xxl` | 4, 8, 12, 16, 20, 24, 32 | everything |
| `Space.sideMargin` | 20 | screen margins |

### The player is not light

The player keeps `#000`, a HUD card at black 62% with a 1 pt white 10% stroke,
and monospaced digits. A light page behind a 3DS picture costs contrast and
attention, and the HUD has to stay readable over any game.

## Motion

Four springs and one fade, all in `Design.Motion`.

| Where | Animation |
|---|---|
| Selection pill, tab switch | `.interactiveSpring(response: 0.34, dampingFraction: 0.86)` |
| Press down / up | `spring(0.18, 0.9)` / `spring(0.26, 0.86)`, scale 0.97 |
| Panel or sheet arriving | `.interactiveSpring(response: 0.42, dampingFraction: 0.88)` |
| Backdrop behind a panel | `.easeOut(duration: 0.25)`, started with the panel |
| Row entrance | `spring(0.46, 0.9)`, 8 pt rise, 20 ms stagger, once |

Rules that follow from those numbers:

- Nothing linear, nothing eased except the backdrop.
- Nothing loops. No pulse, no shimmer, no float. A permanently animating layer
  spends frames the emulator needs.
- Press feedback scales on the way **down** only; releasing never scales.
- Entrance plays once per screen appearance and never on state changes.
- One blurred layer per screen, and never inside an animating view.

## Components

`App/Sources/Design/Components.swift`:

| Component | What it is |
|---|---|
| `DesignCard` | white card, radius 24, soft shadow, section title + optional subtitle |
| `DesignRow` | title, subtitle, trailing control; greys out and stops taking touches when unavailable |
| `RowDivider` | the hairline between rows |
| `ChipRow` | one-of-N choice, accent capsule on the selected chip, selection spring |
| `CircleButton` | 44 pt circular hairline button for the title bar |
| `FloatingCapsuleBar` | blurred capsule container for navigation and other floating strips |
| `CoverCell` | artwork at a given aspect, name, metadata, optional ellipsis |
| `PressableStyle` | 0.97 press scale, spring back |
| `PressHaptic` | one light tick on touch-down, honours the haptics setting |

Reused rather than rebuilt: `BlurBackdrop` (the app's only `UIVisualEffectView`
wrapper) and `GameDetailView`/`PlaybackScreen` keep their own internals until
their phase.

## Placeholders

A setting the app cannot honour yet is a real row with a real title, the subtitle
that says what is missing, and a disabled control. `PlannedFeature` owns the list,
the title, the reason and the availability; enabling one is a one-line change.
Nothing is hidden and nothing is faked.

## Two layouts, one app

The size class decides the arrangement, never the components. Regular width means
iPad full screen or a wide split; compact width means a narrow split or slide
over, which is where the narrow layout must be verified.

**Regular width**

- Navigation at the top: a centred capsule with three segments, the active one in
  a lavender pill, and circular hairline buttons to its right (import, more,
  system list). No bottom bar.
- Library: 3 columns landscape, 2–3 portrait by width. The detail pane slides in
  from the right over roughly the right half; the grid stays visible and dimmed.
- Settings: a single centred column, max width 720.

**Compact width**

- Navigation at the bottom: one floating capsule above the home indicator, three
  items with a symbol over a label, the active item inside a filled accent
  capsule, a badge on Emulation while a game runs. Hit area is the whole item
  rectangle, transparent parts included.
- Library: 2 columns. Detail is a full-screen sheet pushed from the right.
- Settings: full width, 20 pt margins.

Both share the same tokens, the same cell and row components and the same motion.
The app is iPad-only (`TARGETED_DEVICE_FAMILY = 2`); compact width is the iPad in
split view or slide over, not a phone target.

## What Phase 0 changed

Added the tokens, the flag registry, the components above and this file. Renamed
the old `Theme.swift` to `LegacyTheme.swift` so exactly one file is called
`Theme.swift`, and it is the new one. No screen uses the new tokens yet, so the
app looks exactly as it did.

## Open choices

Where the brief was silent I followed the closest Folium behaviour and recorded
it:

- Chip rows are content-sized and scroll-free; a row with more than four options
  becomes a wrapping grid of the same chips if a setting ever needs it.
- `CoverCell` takes its artwork aspect rather than assuming square, because 3DS
  icons are square and a future source may not be.
- Haptics for new components read the existing `hapticsEnabled` setting rather
  than adding a second switch.
