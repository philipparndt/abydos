## Why

Reported 2026-09-16, on 0.21.1: double-clicking the title bar zooms the window
when the click lands between the project capsule and the run buttons, and does
nothing when it lands to the right of them — to the right of the play and
debug buttons and the well that names the configuration (`make`, in the report).
On a small display, a window that has been narrowed loses the capsule and the
pills to the overflow menu first — they are `.standard` priority, the run
control is `.high` — and what is left of the strip is the run control and a
chevron. In that window there is nowhere left to double-click, and the gesture
that would give the window the whole screen is exactly the one that cannot be
made.

The cause is in the code, and it is one missing line. The strip to the right
of the buttons is not empty: it is the run control's own frame, which reserves
about 230 points beside the scheme well for the status of the last run so that
a strip does not grow and move a button when a run finishes. The control's
`mouseDown` decides which of its parts was pressed — play, debug, the chevron,
the scheme well, the cross that clears the status — and when the answer is
none of them it returns, without calling `super`. So the press never reaches
AppKit's frame view. `window-frame` records that the title-bar gesture is
AppKit's to handle and that the app's own strip forwards mouse events "as any
view does" — which is why the region *between* the pills and the buttons
works: nothing there claims the event. The run control claims it and then does
nothing with it.

What the gesture does is not in question and is not changed. The report calls
it full screen; it is AppKit's zoom, the same double-click that every other
window on the machine answers according to Settings ▸ Desktop & Dock, and the
app has done nothing of its own with it since the springback was fixed on
2026-09-09.

There is no originating `.abydos/backlog` item: this comes from the report
above.

## What Changes

- **The run control is no wider than what it does.** It keeps the play and
  debug buttons, the chevron and the scheme well, and nothing else. The room
  it reserved for the status of the last run is given back to the toolbar,
  where it is flexible space — and flexible space is the one kind of item the
  title-bar gesture works through, which is why the room between the pills and
  the buttons always zoomed.
- **The status moves to the title bar.** What the last run said is drawn on
  the backdrop the content view paints under the titlebar, just left of the
  buttons and right-aligned to them, in the width it had before. It declines
  every click but the one on its cross, so a double-click on the message zooms
  the window and leaves the message where it was; the cross still forgets it.
  A message arriving or going moves no button: the run control's position is
  the toolbar's trailing edge either way.
- **The title bar makes its own room, so the toolbar never overflows.** A
  toolbar that has put an item away collapses its flexible space to nothing,
  and the reporter found the narrow window still dead after the status had
  moved: the run control alone at the leading edge, and nothing beside it the
  gesture would work through. Now the capsule shortens its names to the room
  the window leaves, folds away below its minimum, and the pills fold after it
  — decided from the window's width, so the flexible space always stays and
  always fills what is free. There is no overflow menu any more; the project
  switcher and the branch menu are in the menu bar as they were.
- **The zoom instrument aims at the title bar.** `--zoom-gesture click-status`
  posts its four events at the message, or at the room where one would be, and
  says what view was under the point and the responder chain above it;
  `click-clear` presses the cross. A posted event cannot make macOS 26 zoom
  the window — the gesture is decided from the real mouse — so what the
  instrument proves is where a click goes, and a pair of builds tested by hand
  proved what zooms; see design.md.
- **First tried, and withdrawn**: forwarding the unclaimed press from the run
  control's `mouseDown` to `super`, then the release and drags as well, then
  declaring the view movable. A press inside a custom toolbar item never
  zooms, whatever the item does with it; measured 2026-09-16 with two builds
  side by side.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `window-frame`: the title-bar gesture reaches AppKit from every part of the
  strip that is not a pressable control, including the frames of the app's own
  toolbar views, and so from a window narrow enough to show only the run
  control.

## Impact

- **`Sources/AbydosApp/Titlebar/RunControl.swift`**: the status drawing, its
  reserved width and the cross leave; the words stay, and `setStatus` tells the
  title bar through `onStatusChanged`.
- **`Sources/AbydosApp/Titlebar/TitlebarStatus.swift`**, new: the message on
  the backdrop, with its cross, hover and tip.
- **`Sources/AbydosApp/Titlebar/TitlebarController.swift`**: owns the status
  view, places it beside the run control whenever the strip is laid out, and
  hides it when there is no message or no room; fits the strip to the window
  by folding the capsule and pills, and keeps the flexible space at the run
  control's priority.
- **`TitlebarCapsule.swift`, `PillButton.swift`**: a room the names shorten
  to, and folding for want of room, apart from having nothing to say.
- **`MainWindowController.swift`, `+Sessions.swift`, `+Driving2.swift`**: the
  wiring, and the `run:status` hover moving with the message.
- **`MainWindowController+Zoom.swift`**, `LaunchOptions.swift`: the instrument.
- **`openspec/specs/window-frame`**: one requirement added.
- **Release notes**: one `##` for the next version.
