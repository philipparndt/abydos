## Why

Double-clicking the title bar zooms the window and it comes straight back to
the size it was. Reported again on 2026-09-09 by a user and by the maintainer,
who has it every time on a freshly started app, six days after
`a-zoomed-window-stays-zoomed` measured the zoom and found it correct.

It is reproduced now, from outside the process, with the frame sampled by the
window server rather than by the app: a real four-event double-click posted at
the title strip of a window restored from the autosave takes it from 1280×820
to 1920×985 in a fifth of a second and back to 1280×820 by half a second. Every
time, on a fresh window and four seconds after launch alike, and after a small
drag first as well. The window is zoomed twice in one gesture.

**The two zooms have two authors.** The strip across the top of the window is
`ColoredView` with `actsAsTitlebar`, which since 2026-08-06 answers a press
counted twice with `performZoom` — added because "a view swallows a
double-click" and the gesture did nothing. But the strip forwards every other
mouse event to `super`, so the first press of the gesture reaches AppKit's own
frame view and arms its title-bar handling; that handling acts on the *release*
of the second press, which the strip also forwards. Ours zooms on the press,
AppKit's un-zooms on the release. Holding the second press for a second and a
half separates them by a second and a half.

**Why the earlier measurement did not see it.** The instrument sent one press
and one release, both counted twice, straight into `NSWindow.sendEvent`. Nothing
counted once ever went to the frame view, so it was never armed, and the second
toggle never fired. Its "reproduced" springback — a release queued ahead of its
press — was dismissed as the instrument's own lie, and it was; but the mechanism
it stumbled on, a release counted twice reaching AppKit, is the real one.

**Why it began when it did.** The binary people install has been marked as
built against the macOS 14 SDK since 2026-08-26, for the toolbar's sake. Under
that marker AppKit handles a title-bar double-click for a strip like this one
itself; under the macOS 26 SDK marker, measured on the same machine, it does
not act on the release, and the handler added on 2026-08-06 was doing the whole
job. The marker change made it a duplicate, twenty days after it was written.

There is no originating `.abydos/backlog` item: this comes from a direct report,
2026-09-09.

## What Changes

- **The app no longer zooms the window on a title-strip double-click.**
  `actsAsTitlebar` and `TitlebarDoubleClick` go, with their tests. AppKit does
  the gesture, once, under either SDK marker — measured under both with the
  handler switched off: one zoom, and it stays.
- **The instrument sends the whole gesture.** `--zoom-gesture click` posts four
  events — press and release counted once, then counted twice — through the
  application's queue, and reads the frame once the animation is over and again
  a beat later. With the handler in place it now shows the springback; without
  it, one zoom.
- **The requirement says what was found**, replacing the paragraph that said the
  fault was measured and not there.

## Capabilities

### Modified Capabilities

- `window-frame`: a zoom stays — now true because the app stopped zooming
  twice, and the title-bar gesture is stated to be AppKit's to handle.

## Impact

- **AbydosApp**: `WindowViewHelpers.ColoredView` loses its double-click branch;
  `MainWindowController+Zoom` posts the real gesture.
- **AbydosKit**: `Support/TitlebarDoubleClick.swift` removed, with
  `TitlebarDoubleClickTests`.
- **Driver**: `--zoom-gesture click|zoom[+back][@seconds]` unchanged in
  spelling; the readings are at 0.4 s and 1.2 s rather than at once and 0.6 s.
