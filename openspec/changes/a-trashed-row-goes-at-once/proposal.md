## Why

⌘⌫ on a row does nothing visible for as long as it takes the trash to
answer. `trash(_:)` hands the URLs to `NSWorkspace.recycle` and returns
(`ProjectNavigatorViewController.swift:2318`); its completion posts a toast on
failure and records the undo, and nothing in either place touches the tree.
The row goes when the file-system watcher notices the file has left the
directory — after the recycle round trip, which is a cross-process file
operation that takes hundreds of milliseconds and more for a folder, and
after up to 0.25 s of event coalescing when anything else is writing
(`FileSystemWatcher.swift:47`). The app's own driving harness already
budgets 1.5 s for it: the `settle` step defaults to that, with the comment
that a trash-then-⌘Z script "found an empty stack however long it waited".

Reported on 2026-09-04: "when deleting files it takes long till the project
view refreshes and removes the file. Sometimes it takes so long that the user
tries again and gets an error message." The error is the second press:
`trash(_:)` never checks the file is still there, hands the dead URL to
`recycle`, and the toast says *Could not move that to the trash* over a file
that is already in it (`:2321`).

The "sometimes" has a cause of its own. A trashed *folder* arrives from
FSEvents as a must-scan event on the folder itself, which the watcher files
under `directories` as that folder (`FileSystemWatcher.swift:165`). The
handler re-reads only directories the tree has loaded
(`ProjectNavigatorViewController.swift:845`), so a folder that was never
expanded is skipped, nothing is touched, and its row stays until something
else changes its parent.

There is no originating `.abydos/backlog` item. Trashing was built under
0442 and has no OpenSpec requirement; this is its first.

## What Changes

- **A trashed row goes at once.** The rows are taken out of the tree the
  moment ⌘⌫ or *Move to Trash* is pressed, before the trash has answered, and
  the selection moves to the surviving row as it does today. If the trash
  refuses a file, its row comes back with the toast.
- **The trash's answer is still what undo remembers.** The undo record is
  made from the completion as it is now, since only `recycle` knows where in
  the trash each file went.
- **A second press cannot error.** A row whose file is already gone is not
  sent to the trash; the tree is refreshed instead.
- **A collapsed folder's row goes too.** The completion re-reads the parents
  of what was moved, so the tree does not depend on the watcher noticing a
  folder it never listed.
- The watcher's own path is unchanged: it stays the way a file written by
  something else arrives.

## Capabilities

### New Capabilities

- `trashing-files`: what ⌘⌫ and *Move to Trash* do, what the tree shows
  while the trash is at work, what happens when it refuses, and what undo puts
  back.

### Modified Capabilities

None. `tree-behaviour`'s rule for where the selection goes when its rows
vanish is what this already uses.

## Impact

- **AbydosApp**: `ProjectNavigatorViewController.trash(_:)` marks the rows
  doomed and reloads before calling `recycle`; the data source's one walk,
  `rows(under:)`, leaves doomed rows out; the completion clears the mark,
  re-reads the parents, and puts rows back on refusal. `trash(_:)` skips URLs
  that no longer exist.
- **AbydosKit**: a small value, `DoomedRows`, holding the set and answering
  "is this row hidden" and "which parents to re-read" — so the two rules are
  tests rather than view code.
- **Driver**: `cmd-delete`, `rows` and `ls:` already exist; a run shows the
  row gone before `settle`, the file gone after it, and ⌘Z bringing both back.
- **Cost**: one set lookup per row drawn while a trash is out, and none when
  it is not.
