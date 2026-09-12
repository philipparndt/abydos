## Why

The maintainer, 2026-09-11, with four screenshots at a large zoom: the
Backlog pane's *List / Board* switch small beside its counts, the Structure
pane's *Filter symbols* field and its *No file open* label at the size they
had at 1.0, and the Scratches pane's *Search scratches* field the same while
*New Scratch* and *New Global* beside it had grown. A fifth screenshot was
the control that works: the pull-request list's *Only me / My teams too*
switch and the refresh glyph, both at the zoom's size.

The difference is not effort in the panes; it is which of two paths a
control is on. The library in `Controls/ScaledControls.swift` re-takes every
registered member's metrics on `.abydosSettingsChanged` without the pane
being asked — that is why the pull-request list is right. A raw `NSSearchField`
or `NSTextField` given `Theme.current.uiFont` once at build time is right at
that zoom and never again, and the sidebar's panes are told nothing on a zoom:
`SidebarController` forwards no `applySettings`, and the rebuild in
`applyPalette` runs only when the palette changed. `StructurePane.applyThemeChange`
does the right thing and has no caller. `BacklogPane.applySettings` is reached
and re-sets the font, but an `NSSegmentedControl` takes its bezel from
`controlSize`, which is the case `DrawnChoice` was written to replace.

## What Changes

- **The library's measured members where a raw field stands.** The Structure
  pane's filter field and the Scratches pane's search field become
  `ScaledSearchField`; the Structure pane's placeholder, the Scratches pane's
  empty label and the pull-request list's trouble text become `ScaledLabel`.
  Each then re-takes its font and height on its own.
- **`DrawnChoice` for the Backlog pane's two switches** — *List / Board* and
  *Backlog / OpenSpec* — as the pull-request list already has, so the bezel
  grows with the words; its *Refresh* becomes a `DrawnButton` the pane keeps a
  reference to.
- **Row heights re-noted on a zoom** in the Structure and Scratches panes,
  through `ScaledHeights`, so the rows and the section headers re-measure
  rather than waiting for the next data reload.
- **Nothing new in the sidebar's forwarding.** The registry is the mechanism;
  a second path that panes must remember to join is what produced these four.

## Capabilities

### Modified Capabilities

- `scaled-controls`: which panes' fields, labels and switches are members of
  the library, so the promise that a control follows the zoom without being
  told is kept in the four panes it was not.

## Impact

- **AbydosApp**: `Panel/BacklogPane.swift`, `Editor/StructurePane.swift`,
  `Scratch/ScratchesPane.swift`, `Review/PullRequestsPane.swift` (the trouble
  text only). `StructurePane.applyThemeChange` goes, having no caller.
- **Driving**: the zoom report the library's own change measured with, run
  over each of the four panes at 1.0 and 2.0.
