## Why

Widening the window makes the terminal shorter. Dragging the right edge out
takes a row off the panel per resize notification — dozens of them in one drag —
until it reaches its 160 pt floor, and the height somebody set is gone. Reported
with two screenshots, 2026-09-01: the same window, wider, with a panel less than
half the height.

Nothing couples width to height on purpose. The cause is the snap that rounds
the panel down to whole terminal rows, and it is two mistakes standing together:

- **The snap is not a fixed point.** For a horizontal split,
  `setPosition(p, ofDividerAt: 0)` leaves the second subview
  `total − p − dividerThickness` tall, and `dividerPosition` returns
  `total − wanted` with no thickness term. So the panel comes out one point
  short of what was asked, the terminal's usable height becomes
  `k·rows − 1`, and the *new* remainder is a whole row less one point — far
  above the half-point the snap ignores. The comment beside it says "it
  converges in one step: the second pass finds nothing left over and stops",
  and that is exactly what does not happen.
- **A width-only resize asks the question at all.** `NSSplitView` posts
  `didResizeSubviews` for any frame change, width included; the handler filters
  on which split view it is and never on whether the height moved.

Either alone would be invisible. Together they turn every horizontal resize into
a row of terminal.

## What Changes

- The snap accounts for the divider: the panel ends up the height that was
  asked for, so the next remainder is nothing and the snap stops — which is
  what it always claimed to do.
- A resize that did not change the split's height is not a reason to round
  anything: the handler ignores it.
- The same off-by-one is corrected in the three other places that compute a
  divider position as `total − height` — putting the panel away and back,
  making room for the editor, and maximising it — so a panel restored to
  "the height it had" is that height rather than a point less each time.
- A test that the snap is a fixed point: apply it, recompute the state it
  produces, and the answer is nil. The suite asserted the off-by-one instead.

## Capabilities

### Modified Capabilities

- `terminal`: an added requirement — the panel's height is the height it was
  given, and a resize that does not change the height does not change it.

### New Capabilities

<!-- none -->

## Impact

- **AbydosKit**: `PanelRowSnap.State` gains the divider thickness and
  `dividerPosition` subtracts it; `PanelRowSnapTests` gains the idempotence
  case and loses its assertion of the old arithmetic.
- **AbydosApp**: `MainWindowController.splitViewDidResizeSubviews` remembers
  the height it last saw and bails on a width-only pass; three `setPosition`
  callers get the thickness term.
- **Driver**: a run that resizes the window wider and reports the panel's
  height either side.
