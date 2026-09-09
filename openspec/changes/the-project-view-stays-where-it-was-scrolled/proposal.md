## Why

The maintainer, 2026-09-09: *"the project view scrolls randomly up while I am
in the Claude Sessions section and watch screenshots"*. A report about the
navigator's tree, with the two facts that place it: the Claude Sessions part of
the tree, and a session that is taking screenshots at the time.

Reading gives the mechanism a name before anything is measured. Every event a
Claude Code session reports through the hook — a tool call, and a screenshot is
one — reaches the window as `claudeSessionsChanged(slug:)`, and when the slug is
this project's the navigator calls `refreshSessions()`, which reads the
sessions again and puts them on screen through `show(_:)`. That method is
careful about two things and not about a third: it remembers which rows were
expanded and which were selected, calls `outlineView.reloadData()`, and puts
the expansion and the selection back. It does not remember where the list was
scrolled, and `reloadData()` on an outline view does not keep it either. So a
tree somebody has scrolled down to read a session's files jumps to the top
every time that session does anything — which, while it is taking screenshots,
is every few seconds. "Randomly" is the session's rhythm, seen from the other
side.

The file tree has the same shape of refresh — `refreshFromDisk()` on
`windowDidBecomeKey`, and on filesystem events — and may have the same fault
whenever a reload is a `reloadData()`; the sessions tree is where it is felt,
because that is the part of the tree that is rebuilt while somebody is reading
it.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-09.

## What Changes

- **Reproduce first, with a number.** A driven run opens a project with enough
  sessions or files to scroll, scrolls the tree, fires a session event through
  the hook, and prints the scroll position before and after — so the fault is a
  pair of numbers rather than a feeling, and so the fix is measured by the same
  pair.
- **A reload keeps the scroll position.** `show(_:)` and every other rebuild
  that goes through `reloadData()` remember the visible rect — or the top
  visible row, which survives rows being added above it better than a point
  does — and put it back with the expansion and the selection. Decided in the
  design which of the two, from what the reproduction shows when a row is
  inserted above the reader.
- **Rebuild less, where the structure did not change.** The comment at
  `ProjectNavigator+Loading.swift:385` already says it for one path:
  "deliberately not `reloadData()`: the row structure has not changed". A
  session event that changes a row's text and not the tree's shape should
  take that path too.

## Capabilities

### Modified Capabilities

- `project-view`: what a refresh of the tree keeps — expansion, selection, and
  now where it was scrolled.

## Impact

- **AbydosApp**: `ProjectNavigator+Loading.swift`, `show(_:)` and the
  refresh paths that call `reloadData()`; `NavigatorOutlineView` if the
  position is kept there.
- **Driver**: a verb that scrolls the tree and prints its position, and a way
  to fire a session event without a real Claude session.
