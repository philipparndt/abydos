## Why

Reported: the tmux window tabs along the bottom of the panel do not handle
overflow, and there should be a chevron listing the windows that do not fit —
"like for the other tab bars".

They were meant to. `tab-overflow` already requires every strip to offer a way
to any tab it holds, and `PanelTabStrip` measures the run, counts what is
hidden, reserves the chevron's room, answers a click on it and builds the menu
— on every strip, tmux's included. Only the *drawing* sat behind
`guard showsPanelControls else { return }`, which is false on the two strips
that have no panel controls: tmux's mirroring strip, and a torn-off terminal
window's.

So on those two the control was counted, reserved and clickable with nothing
drawn to say so — a 34-point invisible target beside the last window, and a
list of tmux windows that simply stopped.

## What Changes

- **The chevron is drawn on every strip**, whether or not the panel's own
  controls belong there. It already draws itself in tmux's green when it is
  tmux's strip, which says how the omission happened: everything but the call
  was in place.
- The panel's own trailing controls move into a function of their own, so the
  guard says what it is guarding.
- **A driver can fill tmux's strip.** `--tmux-tab-fill 16` seeds the mirroring
  strip with windows and says what it does with them, because a real
  `tmux list-windows` never arrives inside a driven run and that is why this
  shipped.

## Capabilities

### Modified Capabilities

- `tab-overflow`: says that the control belongs on every strip, not only on one
  that carries the panel's controls.

## Impact

- **AbydosApp**: `PanelTabStrip.draw` reordered; a seeding hook and a launch
  flag.
- **No layout change.** The room was already reserved on these strips, so the
  tabs do not move — the chevron appears where the gap already was.
