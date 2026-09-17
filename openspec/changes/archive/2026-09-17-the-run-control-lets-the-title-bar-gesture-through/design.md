## Context

See proposal.md for the report and the cause.

The strip is a real `NSToolbar` in `.unified` style on a window with
`fullSizeContentView`. Its items are the app's: the capsule, three pills, a
flexible space, and `RunControl`. Under the toolbar the content view paints a
backdrop across the title bar's height, with the seam along its bottom.
`window-frame` already settles who handles the double-click — AppKit, with the
app doing nothing of its own — and how that used to be proved: `--zoom-gesture
click` posts the four events of a double-click and reads the frame before,
after and a beat later.

`RunControl` drew its parts itself: the buttons, the well, and the message of
the last run in room reserved beside the well so a message arriving would not
move the buttons. Its `mouseDown` was an `if`/`else if` over those parts with
no final `else`.

## Goals / Non-Goals

**Goals:**

- The room to the right of the buttons zooms the window as the room to the
  left of them does, and a window showing only the run control can be zoomed.
- The message of the last run is still readable in the strip, still clears
  from its cross, and its arrival moves no button.

**Non-Goals:**

- Changing what the gesture does. The machine's setting decides.
- Making the capsule or the pills zoom. A press on them is a press on a button.

## Decisions

### 1. The status leaves the toolbar item

`RunControl` shrinks to the buttons, the chevron and the well. The message is
`TitlebarStatus`, a view on the backdrop, placed by `TitlebarController` just
left of the run control and right-aligned to it, up to the width the control
used to reserve and no wider than the room between it and the last pill
showing. The control keeps the words — `setStatus` is called from sixty places
and stays — and tells the title bar through `onStatusChanged`.

The room the control gives back becomes flexible space, and flexible space is
what the gesture works through: see *What was measured*. A message arriving or
leaving moves nothing, because the control's position is the toolbar's trailing
edge either way; the old reservation was guarding against a strip that grew,
and a strip that does not hold the message cannot grow.

*Ruled out, by measurement: forwarding from the control.* `super.mouseDown`
for an unclaimed press reached `NSWindow.mouseDown` with click count two, the
same handler a press on the backdrop reaches — and did not zoom. Forwarding the
release and the drags to the content view as well did not. Declaring
`mouseDownCanMoveWindow` did not. A build with the control shrunk zoomed at
once, beside those. Whatever AppKit consults, it is not the events.

*Ruled out: `hitTest` returning `nil` for the room.* The hit then lands on the
toolbar's own item viewer, which is still the item's region.

*Ruled out: keeping the message in the toolbar as an item of its own.* A
second custom item is a second dead region.

### 2. The message gives the room back

`TitlebarStatus.hitTest` answers only for the cross. Everywhere else the click
falls through to the backdrop, so a double-click on the text is a double-click
on the title bar, and the text is untouched by it. The hover and the tip need
no hit: the tracking area is a rectangle the window watches. The cross keeps
its hover ground and gains a tip; the message shows its full text as before.

### 3. Placed by frame, asked again a moment later

The run control is the toolbar's to move, on its own turn of the run loop, so
the status is placed from the control's frame converted into the backdrop —
when a message is set, when the strip is re-laid for a theme change, and when
the window's inset is set on a resize, each followed by one more pass on the
next turn. It hides when there is no message, when the run control is in the
overflow menu, or when less than sixty points are left for it.

*Ruled out: constraints across the toolbar and the content view.* Both hang
off the same frame view, and a constraint between them can be written; it
would also be a constraint against a private view hierarchy that the toolbar
rebuilds when items move to the overflow menu.

### 4. The instrument says where a click goes, not whether it zoomed

`--zoom-gesture click-status` aims at the message, or at the room where one
would be, and prints the view under the point and the responder chain above
it; `click-clear` presses the cross. Under macOS 26.7 a posted `NSEvent` does
not zoom a window from anywhere, and a real event from a helper is refused
without Accessibility trust. So the instrument's honest reading is the route,
and the zoom was proved by hand, twice, with builds that differed in one
thing.

### 5. The title bar fits the strip, so the toolbar never overflows

With the status moved, the reporter's narrow window was still dead: the
toolbar had put the capsule, the pills *and the flexible space* away, laid the
run control at the leading edge, and the stretch beside it was the backdrop —
which the gesture does not work through either, measured by hand. A toolbar in
overflow collapses its flexible space; keeping the space at the run control's
priority kept it *visible* and still collapsed to nothing.

So the toolbar is never allowed to overflow. `fitStrip`, from the window's
width less the traffic lights, the run control, the toolbar's paddings and a
stretch of flexible space to double-click on: the capsule takes what is left
as `roomWidth`, shortening its names to it, and folds away when that is under
its minimum; if it folds, the pills fold with it, since each qualifies the
project it names; otherwise the pills fold one at a time, devcontainer last,
as room runs out. Folding is `isCollapsedForRoom` on the views — hidden and a
sliver wide, apart from `hasContent`, which is the old reason a pill was
hidden. It runs on the window's inset changing, on the strip's re-layout, and
when a name, branch, worktree, subproject or container is set; it reads
nothing back from the toolbar, so nothing flickers.

*Given up: the overflow menu.* The capsule's menu form offered *Switch
Project…* and *Branch…*, which are in the menu bar; the pills' menus are lost
in a window too narrow to show them, which is the window in which nothing was
zoomable at all.

*Ruled out: removing and reinserting the items.* It is what the toolbar does,
and the delegate would build fresh views whose state — branch, worktree,
container — would have to be re-applied from four places.

## Risks / Trade-offs

- **The fit's constants are estimates of the toolbar's paddings.** Generous
  ones, with a 120-point reserve; an estimate too small would let the toolbar
  overflow again, which the toolbar report in a driven run shows at once.


- **The message has less room in a narrow window.** It shares the flexible
  space with nothing, but when the pills leave less than sixty points it hides
  rather than overlap them. The toast and the launch log still have it.
- **A frame placed by hand can lag a toolbar re-layout by a turn.** The second
  pass on the next turn covers the cases seen; a resize during a live drag
  re-places it on every `windowDidResize`.
- **The status' hover and tip depend on the tracking area, not the hit.**
  Should that ever change, the message would lose its tip and nothing else.

## What was measured, 2026-09-16

Debug and release builds under throwaway identifiers, unpinned UUID, Xcode
26.6 toolchain on macOS 26.7, on a scratch repository under the session's
scratchpad, load average 3 to 9 over 14 cores.

**The fault.** At this machine's theme scale a 1280-wide window put the
capsule and all three pills into the overflow menu, so the strip was the run
control (789×28) and nothing else — the reporter's narrow window, unasked for.
`--zoom-gesture click-status@3` landed on `RunControl` and the frame stayed
1280×820 through all three readings.

**Forwarding, traced.** A temporary swizzle, not committed, logged
`mouseDown:`/`mouseUp:` on the AppKit classes in the chain:

| Class | overrides |
|---|---|
| `NSToolbarItemViewer` | `mouseDown:` `mouseUp:` |
| `NSToolbarView` | `mouseDown:` |
| `NSTitlebarView` | `mouseDown:` |
| `NSTitlebarContainerView` | `mouseUp:` |
| `NSThemeFrame` | `mouseDown:` `mouseUp:` |
| `NSWindow` | `mouseDown:` |

A posted double-click on the backdrop went `ColoredView ×4 → NSWindow.mouseDown`
for each press. The same click on a run control forwarding to `super` went
`RunControl → NSToolbarItemViewer → NSToolbarView → NSTitlebarView →
NSTitlebarContainerView → ColoredView ×4 → NSWindow.mouseDown`, counted 1 then
2 — the same handler, the same count. The release stopped at
`NSToolbarItemViewer.mouseUp`. Neither posted click zoomed, and nor did one on
the backdrop; `--zoom-gesture zoom` did. A helper posting real events through
the HID tap was refused: the terminal is not trusted for Accessibility.

**By hand, the reporter.** The forwarding build zoomed once and then never
again. With the release and drags forwarded to the content view: not at all.
Then two builds side by side — **A**, the run control shrunk to its buttons
and well with flexible space either side; **B**, the room kept, the control
forwarding everything and declaring `mouseDownCanMoveWindow`. A zoomed from
the room right of the well; B did not. The room that works is the flexible
space's, and the instrument confirms the hit there is `_NSToolbarFlexibleSpace`
inside an `NSToolbarItemViewer` — an item, but the one kind AppKit lets the
gesture through.

**After the status moved, the reporter's narrow window.** Still dead. The
instrument at 800 points wide: `TOOLBAR visible=["abydos.run"]`, the run
control at x = 92, the flexible space collapsed although at `.high` priority,
and the free strip beside the control hitting `ColoredView` — the backdrop,
which a real double-click does not zoom from.

**With the fit.** At 800, 1000, 1280 and 1600 points wide the toolbar report
shows every item present and nothing put away, the run control at the
trailing edge, and `click-status` landing on `_NSToolbarFlexibleSpace` each
time. A screenshot at 800×600 shows the capsule folded, no overflow chevron,
`Failed — exit code 2` beside the play button and the strip free to its left.

**The structural build.** `click-status` with no message lands on
`_NSToolbarFlexibleSpace` left of the buttons; with `Failed — exit code 2`
showing, the same, and a posted double-click there leaves the message reading
the same; `click-clear` lands on the cross, the message clears and the frame is
unchanged. A screenshot shows the message right-aligned to the play button,
red, with its cross, and the run control at its new width.

## Open Questions

None.
