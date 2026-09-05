## Why

**⇧⌘A puts its list in the middle of the window and ⇧⌘P puts its list in the
top-left corner**, and they are the same gesture: a key pressed by somebody
looking at the middle of a wide window, answered by a list that has to be
found. ⇧⌘A opens `RunningSessionsPalette` — a `PalettePanel` centred
horizontally on the window that answered the key, near its top, with a driven
report (`placementForTesting`) that says so. ⇧⌘P opens
`ProjectSwitcherPopover` as an `NSPopover` anchored to the project pill,
because the pill is what a *click* opens it from, and the key was given the
click's geometry.

Asked for on 2026-09-05: "the agent dialog is opened at the center of the
window when open with the shortcut, which ist nice. I think we should do the
same for the palette (shift + cmd + P)."

No originating backlog item: asked for directly on 2026-09-05.

## What Changes

- **⇧⌘P opens the switcher centred on the window that answered it**, near the
  top, in the same `PalettePanel` `RunningSessionsPalette` and
  `SymbolPalette` already use — one geometry for every list a key opens, and
  the pointer nowhere near the corner it used to be dragged to.
- **A click keeps the geometry a click deserves.** The project pill, the
  branch pill and the run control still open their popover anchored to
  themselves: a list that appeared in the middle of the window when somebody
  clicked a control in the corner would have lost the thing it is about.
- **The list itself does not change.** The same controller, rows, filter
  field, arrow keys, ⏎ and Escape — as ⇧⌘A's two windows already share one
  controller, which is what makes this a placement change and not a second
  palette.
- **Escape and the key again close it**, as they do for ⇧⌘A, and the panel is
  a child of the window that opened it, so it follows that window.

## Capabilities

### New Capabilities

- `command-palette`: what ⇧⌘P opens, where it appears when a key opens it and
  where when a control does, and what closes it.

### Modified Capabilities

<!-- None: no existing requirement says where the switcher appears. The
`running-sessions` requirement that puts ⇧⌘A's list over its window stays as
it is; this change gives ⇧⌘P the same rule in its own capability. -->

## Impact

- `Sources/AbydosApp/Titlebar/ProjectSwitcherPopover.swift` — the controller
  it builds is put in a `PalettePanel` when the caller is a key, and in the
  `NSPopover` it uses today when the caller is a control; one `show` with the
  caller's intent, rather than two lists.
- `Sources/AbydosApp/AppDelegate.swift` — the ⇧⌘P item asks for the key's
  placement; the pill, the branch pill and the run control ask for the
  anchored one.
- No new window class, no new controller: `PalettePanel` exists and already
  carries Escape, the theme and the resign-key close.
