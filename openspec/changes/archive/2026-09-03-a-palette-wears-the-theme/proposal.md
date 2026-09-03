## Why

Reported, with a picture: the top of the window ⇧⌘A opens does not follow the
theme. On a light theme the list came up light, with a dark strip across the top
holding a dark-bezelled search field.

Everything a palette *draws* comes from `Theme.current`. The band across the top
is not drawn by us: it is the title bar's own material, and the field's bezel is
a system control. Both follow the **window's appearance**, which nothing had
set — so it was whatever the Mac happened to be in, and on a dark Mac with a
light theme the two halves of one window belonged to different programs.

The popover under the pill has taken its appearance from the theme since the day
it was written. The palette windows never did. `SymbolPalette` — the same window
class, opened by ⇧⌘O — has the same fault and was not reported only because
nobody looked at it in a mismatched pair.

## What Changes

- **A palette window wears the theme on every showing**, in `PalettePanel`
  rather than in each palette: `orderFront` and `makeKeyAndOrderFront` set the
  appearance and the ground from `Theme.current` before the window appears.
- Both palettes are fixed by that, and so is the next one.
- On every showing rather than at construction, because a palette keeps its
  window between openings and the theme can be changed while it is put away.

## Capabilities

### Modified Capabilities

- `theme-access`: says that a window the app makes takes its appearance from the
  theme, not from the machine.

## Impact

- **AbydosApp**: `PalettePanel` overrides the two ways it is shown; the
  running-sessions palette drops the line it was setting at construction.
- **Both palettes**: ⇧⌘A's list and ⇧⌘O's symbols.
