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

**Nothing about the window's behaviour, and that is the finding.** The report
could not be reproduced against the app: from a frame restored at launch and
untouched, the gesture zooms and stays zoomed, and a second one returns the
window. What reproduced the symptom every time was the instrument written to
look for it — a synthesised mouse-up carrying `clickCount: 2`, queued ahead of
its press, read by AppKit as a second double-click, so every gesture zoomed
twice.

- **The zoom is measured, and the measurement is what this change leaves.** A
  driving verb double-clicks the title bar and reports the frame and `isZoomed`
  three times — before, immediately after, and a beat later — because a
  springback is two frame changes and one reading cannot tell them apart.
- **`windowWillUseStandardFrame` was tried and reverted.** With it in place a
  zoomed window could not be un-zoomed. AppKit's guess was already the visible
  frame, and taking the decision over broke the `isZoomed` an un-zoom depends
  on. That the standard frame is AppKit's to choose is now a requirement, so
  the next plausible fix meets a stated one.
- **The cause is written down rather than a fix guessed at.** An intermittent
  frame fault is exactly the shape that punishes a plausible fix: it will
  appear to work.

## Capabilities

### New Capabilities

- `window-frame`: what the window does with its own size — what a zoom aims at,
  that a zoom stays, and what is remembered between sittings. Nothing states any
  of this today; the frame is left to AppKit and its autosave.

## Impact

- **AbydosApp**: no behaviour change. `MainWindowController+Zoom` is new and
  holds the instrument, including the note about the queued release that made
  the symptom.
- **Driver**: `--zoom-gesture click|zoom[+back][@seconds]`.
- **Left unproven**: the gesture on a window moved first, because in a
  900-point window the synthesised click lands on one of the app's own titlebar
  views rather than the title bar; and the torn-off terminal windows, which
  have no fault to be compared against since none was found here.
