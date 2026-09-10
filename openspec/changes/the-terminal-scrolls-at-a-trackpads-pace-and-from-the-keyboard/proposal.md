## Why

A colleague of the maintainer, 2026-09-10, in two messages: *"Scrollgeschwindigkeit
im Terminal ist sehr hoch — kommst Du damit klar?"* and *"Das mit dem Scrollen
geht mir auf den Geist :) Gibt es da Tastatur-Shortcuts?"* — the scroll speed in
the terminal is very high, it is getting on his nerves, and are there keyboard
shortcuts. The maintainer has no such trouble on the same build, and asked
whether a trackpad explains the difference. The colleague confirmed the
trackpad; the maintainer scrolls with a mouse wheel.

Reading finds the mechanism before anything is measured. `TerminalView.scrollWheel`
has three paths. Ordinary shell output with scrollback goes to `super`, which
is the native scroll view at whatever pace macOS gives every app. A program on
the alternate screen is sent arrow keys, and a program tracking the mouse — which
inside `tmux` with `mouse on` is every program — is sent wheel reports. Those two
paths share one formula, at `TerminalView+Mouse.swift:496` and `:519`:

    let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))

A mouse wheel raises one event per notch carrying a delta of about ten points,
which is under a cell height, so the formula gives one line per notch — and that
is what the maintainer sees. A trackpad raises sixty to a hundred and twenty
events a second while the fingers move, and more during the momentum phase after
they lift, each carrying the distance moved since the last one. **The `+ 1`
makes every one of those events at least one line**, whatever its delta: a slow
drag of one cell height arrives as perhaps ten events of a point or two and moves
ten lines; a brisk flick carries twenty to eighty points per event, so two to
five lines per event at event rate, plus momentum — several hundred lines a
gesture. The formula dates from the commit that added mouse reporting
(31b4562a, 2026-07-30) and was plainly tuned against a wheel.

The second message has a plainer answer: there are no keys. `keyDown` sends every
key to the program, Page Up, Page Down, Home and End included, and nothing in the
view responds to a page-scroll action. The only way to read history is the
device that is too fast.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **Reproduce first, with a number.** A driven run opens `less -N` on a long
  file in a pane and posts, from a separate process, what a trackpad posts: many
  small pixel-unit scroll events. The line number at the top of the screen
  before and after is the fault as a pair of numbers, and the fix is measured by
  the same pair.
- **A precise device scrolls by the distance the fingers moved.** Deltas from a
  device that reports precise deltas — a trackpad, a Magic Mouse — are
  accumulated across events, one step is sent per whole cell height, and the
  fraction is carried into the next event. A gesture that begins, or reverses,
  starts from nothing carried. A wheel that does not report precise deltas keeps
  exactly the formula it has, so a mouse feels no change.
- **The scrollback has keys.** ⇧⇞ and ⇧⇟ move the view a page, ⇧Home and ⇧End
  to the ends of history, on the normal screen only. On the alternate screen
  there is no history to move through and the keys reach the program as they
  do today, as do the unshifted keys everywhere.

## Capabilities

### Modified Capabilities

- `terminal`: what a wheel event is turned into for a program, and which keys
  the pane keeps for its own scrollback.

## Impact

- **AbydosKit**: a `WheelSteps` accumulator and a `TerminalKeys.scrollbackMotion`
  table, both without a window so the arithmetic is a test.
- **AbydosApp**: `TerminalView+Mouse.swift`, the two wheel paths; `TerminalView+Input.swift`,
  the shifted keys before the program sees them; `TerminalView+Drawing.swift`, the
  page motion.
