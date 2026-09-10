## Why

The maintainer, 2026-09-10: *"when settings is open in one workspace and
switching back to this, the terminal is minimized. This should only happen when
settings is initially opened and not when it is just restored."*

Opening the settings page does this on purpose. `showSettingsPage` in
`MainWindowController+Running.swift` begins with `leaveTerminalFullScreen()`,
because a page opened into an editor the terminal has taken the whole window
from is a page nobody can see — the same reason a file opened from the tree, a
breakpoint hit and a compare page do it. That is right the first time. It is
wrong every time after: a settings page that is already open, in a window
somebody has since given the terminal to, comes back into view when its
workspace does, and the terminal is un-maximised under them with no gesture of
theirs behind it.

Which path runs it on the way back is the first thing the design has to name.
`leaveTerminalFullScreen` has eight callers, most of them "something was
opened" — a file with focus, a pinned page, a compare — and one of them, or a
restore that re-opens the page through `showSettingsPage`, fires when the
window's workspace comes to the front. The report says it does; the code says
which.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **Find the path that runs on return**, with a driven run: the settings page
  open, the terminal maximised, the window deactivated and activated again —
  or its space switched, if that is what it takes — and `isPanelMaximized`
  printed before and after.
- **Opening leaves full screen; being shown again does not.** Whatever the
  path, the rule: `leaveTerminalFullScreen` runs for the gesture that *opens*
  a page and not for a page that is already in the group and merely comes
  back into view. The same rule for every page that opens this way, since the
  settings page is one of several.
- **The terminal's state survives a workspace switch**, maximised or not,
  which is the claim the run measures.

## Capabilities

### Modified Capabilities

- `control-affordances` or `editor`, whichever the design places it in: what
  opening a page does to a maximised terminal, and what restoring one does
  not.

## Impact

- **AbydosApp**: `MainWindowController+Running.swift` (`showSettingsPage`),
  `MainWindowController+Layout.swift` (the eight callers of
  `leaveTerminalFullScreen`), and `windowDidBecomeKey`.
- **Driving**: a step that reports `isPanelMaximized`, and a run that
  deactivates and reactivates the window.
