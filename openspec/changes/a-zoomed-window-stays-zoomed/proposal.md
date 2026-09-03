## Why

Double-clicking the title bar zooms the window and it springs straight back to
the size it was. Reported on 2026-09-03, with the two facts that make it worth
chasing rather than guessing at: **sometimes**, and *"it happens with the
current window; when then moving the window to another position or changing the
size it works"*.

What reading has ruled out already. Nothing in this app puts the main window's
frame back: every `setFrame` outside the driven-run helpers belongs to a picker,
a sheet or a torn-off terminal, and the two in `AppDelegate` are behind
`--window-width` and `--resize-width`. So the spring back is AppKit's, and the
app is not telling it what to do — neither `windowWillUseStandardFrame` nor
`windowShouldZoom` is implemented, so the frame a zoom aims at is entirely
AppKit's own guess about a window that is unusual for it: `fullSizeContentView`,
a title bar we draw ourselves, and a frame restored at launch by
`setFrameAutosaveName`.

That last part is what the report's second sentence is about. A frame restored
from the autosave underneath AppKit is not a frame somebody set, and moving or
resizing the window once replaces it with one that is — after which the zoom
behaves. An intermittent fault with a "and then it works" attached is a state
problem, and naming the state is the work.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-03.

## What Changes

- **The window says what a zoom aims at.** `windowWillUseStandardFrame` returns
  the screen's visible frame, so the zoomed size is this app's answer rather
  than a guess, and is the same answer every time.
- **A zoom stays.** Double-clicking the title bar once zooms and leaves the
  window zoomed; double-clicking again returns it to the size it had. Whatever
  the state of the autosaved frame at launch.
- **The cause is written down before the fix, and if it cannot be reproduced
  that is said.** An intermittent frame fault is exactly the shape that punishes
  a plausible fix: it will appear to work.

## Capabilities

### New Capabilities

- `window-frame`: what the window does with its own size — what a zoom aims at,
  that a zoom stays, and what is remembered between sittings. Nothing states any
  of this today; the frame is left to AppKit and its autosave.

## Impact

- **AbydosApp**: `MainWindowController` gains `windowWillUseStandardFrame`, and
  possibly `windowShouldZoom` if the diagnosis says the veto is where the
  springback comes from. The autosave stays: remembering the window is wanted,
  and the driven-run carve-out around it is untouched.
- **Driver**: a verb that double-clicks the title bar and reports the frame
  before, after, and a moment later — the springback is two frame changes in
  quick succession, and a report taken once cannot tell them apart.
- **Risk**: it may not reproduce. Then the change says so plainly and fixes
  only what can be shown to be wrong — that the zoom target is unstated — rather
  than claiming the report closed.
