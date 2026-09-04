## Why

Asked for, with a picture of the terminal's title bar: the controls at its
trailing end should light up under the pointer, and should have tooltips
explaining themselves — "what is gray/orange on the agents element, what is the
agents element even".

That last question is the one worth reading twice. The sessions pill is two
coloured dots and two figures, and nothing anywhere on screen says what they
count. Its colours are the tab badges' own, which is an argument for somebody
who already knows the badges; for anybody else it is a pill that says `0 · 0`.

And half the strip answered the pointer while the other half did not. The tabs
have had a hover since they were drawn — the controls beside them never did, so
they sat there looking like a picture of controls.

## What Changes

- **Every trailing control lights up under the pointer**, in the tabs' own
  hover shape: a rounded band in the faintest ink the theme has.
- **Twice as much for the two that have grounds of their own.** The pill and
  the `tmux · session` tag are drawn on a tint already, and the band that reads
  clearly behind a bare glyph vanished behind them — checked against the pixels
  rather than assumed. Those two get a capsule halo instead.
- **Every one of them says what it is.** The pill says what the two colours
  count and that a finished session is in neither; the tag names the tmux
  session and what clicking it does; the rest say what they do and the key that
  does it too.
- **A run can ask.** `--hover-control sessions` puts the pointer on one and
  prints whether it lit and what it would say.

## Capabilities

### Modified Capabilities

- `terminal`: the strip's trailing controls answer the pointer and say what
  they are.

## Impact

- **AbydosApp**: `PanelTabStrip` names its trailing controls, tracks which one
  is hovered, draws a ground for it, and answers tooltips for them from the
  point — the same way it already answers a tab's engine note.
- **Tooltips are re-registered only when a frame moves**, not on every layout:
  this strip re-lays out twice a second while a tmux session is watched, and
  tearing a tooltip down under the pointer is how a flickering tip is made.
