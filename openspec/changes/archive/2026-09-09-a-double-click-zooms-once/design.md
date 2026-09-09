## Context

The main window is `fullSizeContentView` with a transparent title bar, and the
strip where the title bar would be is `ColoredView` with `actsAsTitlebar`. Since
2026-08-06 that view has answered a mouse press with `clickCount == 2` by
calling `TitlebarDoubleClick.perform`, which reads the system's
`AppleActionOnDoubleClick` and calls `performZoom`. Every other mouse event
goes to `super`, and so up the responder chain to AppKit's frame view.

`a-zoomed-window-stays-zoomed` (archived 2026-09-03) measured the gesture with
a driven verb, found one zoom that stayed, and left the report open with the
note that the reporter's window state — displays, sleep, a full-screen space —
was what a fresh process could not have.

## What was measured, 2026-09-09

An external driver posts real mouse events through the HID event tap at the
title strip of a driven window, and samples the window's bounds from the window
server every thirty milliseconds. Six runs, each from the frame the real app
remembers (`349 979 1280 820 0 0 1920 1050`, constrained on restore to
349,230 1280×820):

| Binary marked as | App's handler | Gesture | Result |
|---|---|---|---|
| macOS 14 SDK (what is installed) | on | double-click at 0.7 s | 1920×985 at 0.2 s, **1280×820 at 0.56 s** |
| 14 | on | same, 4 s after launch | same springback |
| 14 | on | 20 px drag, then double-click | same springback |
| 14 | on | 30 px drag down, then double-click | same springback |
| 14 | on | second press held 1.5 s | zoom on the press; un-zoom after the release |
| 14 | **off** | double-click | 1920×985 at 0.26 s, still there |
| 14 | off | drag down, then double-click | one zoom, stays |
| macOS 26 SDK (`GLASS=1`) | on | double-click | one zoom, stays |
| 26 | off | double-click | one zoom, stays |

And the app's own instrument, once it posts all four events and records the
largest frame the window passed through:

| Binary marked as | App's handler | `--zoom-gesture` | Result |
|---|---|---|---|
| 14 | on | `click@1` | at 0.4 s 1920×985 zoomed; **at 1.2 s 1280×820**, largest 1920×985 |
| 14 | off | `click+back@1` | 1920×985 at 0.4 s and 1.2 s; back at 1280×820 at 0.4 s and 1.2 s |
| 26 | on | `click@1` | 1920×985, stays |

The held press is the decisive row: the first toggle happens on the second
press, where `ColoredView.mouseDown` is, and the second waits for the second
release, which the view forwards to AppKit. Two zooms, two authors.

The small-drag rows are here because the reporter finds that moving the window
slightly first makes it behave. That did not reproduce with a synthetic drag,
sideways or down; the runs are recorded rather than the observation argued
with. It does not bear on the fix, which removes one of the two authors.

## Decisions

**Remove the app's handler rather than suppress AppKit's.** AppKit zooms the
window once, on its own, under both SDK markers when the strip stops doing it —
which is the state the last two rows of the table describe. A window whose
gesture is AppKit's behaves like every other window on the machine, including
whatever Settings ▸ Desktop & Dock says about it, which is what
`TitlebarDoubleClick` was reading by hand.

*Ruled out: swallowing the second release in `ColoredView.mouseUp` so AppKit's
path never completes.* It would work today, under the 14 SDK marker, and it
would rest on knowing which of the four events AppKit acts on — knowledge this
change has only because it held a mouse button down for a second and a half.
The next SDK marker could move it.

*Ruled out: keeping the handler for the 26 SDK marker and dropping it for the
14.* The 26 SDK rows say AppKit handles the gesture there too when the strip
stops. There is no marker under which the handler is needed.

*Not explained: why the gesture "did nothing" on 2026-08-06.* The measurement
says a strip that forwards to `super` gets AppKit's zoom under either marker.
Whatever was different that day — the view, the window, the machine — is not
recoverable from the commit, and the fix does not depend on it.

**The instrument sends the first click too.** `doubleClickTitleBar` posts press,
release, press, release with `clickCount` 1, 1, 2, 2 through `NSApp.postEvent`,
so the run loop delivers them a turn at a time as a mouse would and a press
that runs a tracking loop finds its release already queued. Sending only the
second pair is what let the earlier measurement pass: nothing counted once
reached the frame view, so it was never armed. The readings move to 0.4 s and
1.2 s after the gesture, because a posted click and a zoom animation both take
turns of the run loop to finish.

## Open Questions

- The reporter's "move it slightly and it works". Not reproduced with a
  synthetic drag; possibly a different spot under the pointer after the move.
  Moot once there is one zoom.
