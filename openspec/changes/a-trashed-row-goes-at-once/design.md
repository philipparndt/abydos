## Context

`trash(_:)` (`ProjectNavigatorViewController.swift:2302`) filters out the
root, calls `NSWorkspace.shared.recycle(urls)` and returns. The completion
(`:2318`) toasts on error and records `FileUndo.trashed(moved)` — the
dictionary from original URL to trash location that only `recycle` can
supply, because the trash renames on collision. The tree is not told
anything; the row leaves when the watcher's handler re-reads the directory.

The watcher coalesces over 0.25 s (`FileSystemWatcher.swift:47`) with
`NoDefer`, so a lone event on an idle project is prompt and a trash during a
build waits out the window. The handler (`:801`) asks for git status first,
but that is a coalesced `Task` and not a wait on this queue — the cold
`git status --ignored` measured at 0.41 s (`:619`) runs beside the reload,
not in front of it. What is in front of it is the recycle round trip, and
for a collapsed folder, nothing at all: the must-scan event names the folder
(`FileSystemWatcher.swift:165`), the handler skips nodes without loaded
children (`:845`), and the row stays.

`trashSelection` (`:2278`) works out the surviving row before anything goes
and sets `pendingReveal`, which the eventual reload honours. Every walk of the
tree goes through `rows(under:)` (`:3509`), which is what makes hiding a row
in one place possible.

## Goals / Non-Goals

**Goals:**

- The row is gone the moment the key is pressed, and the selection is on the
  survivor.
- A refused file's row comes back, with the reason.
- ⌘Z after a trash still puts the file back where it was, from the trash's
  own answer.
- A second ⌘⌫ on a row whose file is gone never errors.
- A trashed collapsed folder's row goes without the watcher.

**Non-Goals:**

- Making `recycle` faster. `FileManager.trashItem` is in-process and quicker,
  but the row's departure is what is felt, and once it is immediate the
  trash's own time is invisible. Kept as a note in *Open*.
- A confirmation dialog. Trash is recoverable and has never asked.
- Changing what the watcher re-reads. Its rule is right for files written by
  others; the trash simply stops relying on it.

## Decisions

### The rows are hidden, not removed

A `DoomedRows` set of URLs, marked before `recycle` is called, and
`rows(under:)` leaves a doomed node out. `reloadData` then draws the tree
without them. The completion clears the set, re-reads the parents and reloads.

*Ruled out:* removing the child from `FileNode`. `FileNode` has no removal;
its children are what the directory says, re-read by
`reloadPreservingIdentity`. A removal that the next re-read undoes is a lie
with a short life, and a removal that survives re-reads is a second source of
truth about what a directory holds. Hiding leaves the node's view of the disk
honest and changes only what is drawn.

*Ruled out:* `outlineView.removeItems(at:inParent:)`. It animates a row out of
a data source that still reports it, and the next `reloadData` — the watcher's,
a moment later — brings it back for the trash's remaining time.

### The undo record stays in the completion

`remember(FileUndo.trashed(moved))` is made from `recycle`'s answer, as today.
An undo made before the answer would have no trash locations to restore
from, which is the fault 0442 fixed. The row leaving early does not change
when the undo exists; it changes what is on screen while it does not yet.

### A refusal puts the row back

When `recycle` reports an error, the URLs it did not move are taken out of the
doomed set and the parents reloaded, so the row returns beside the toast. What
it did move stays gone and is recorded, as now.

### A file that is already gone is not sent

`trash(_:)` drops URLs that `fileExists` says are gone. When that leaves
nothing, it reloads the parents instead of calling `recycle`: the row was
stale, and a refresh is the honest answer to a key pressed at a stale row.
With rows hidden at once this should not happen, but the stale-row case has
other causes — a file deleted in a terminal — and the toast was never the
right reply to it.

### The completion re-reads the parents

The parents of `moved.keys` get `reloadPreservingIdentity` and the tree
reloads, so a collapsed folder's row goes whether or not the watcher ever
names its parent. The watcher's handler is not changed.

*Ruled out:* teaching the handler to re-read a must-scan directory's parent.
It would fix this case and re-read a parent on every build burst, which is the
cost the handler was written to avoid.

### `refreshGitStatus` stays where it is

It looked like a wait in front of the reload and is not: it is a coalesced
`Task`, and the handler goes on to the rows in the same call. Moving it would
change nothing measurable.

### The proof is driven

The harness's `settle` is the number under test: `cmd-delete,rows` shows the
row gone with no settle at all; `settle,ls:` shows the file gone; `undo-key,
settle,rows,ls:` shows both back. The 1.5 s stays as the trash's own time.

## Risks / Trade-offs

- [A doomed row is hidden and the trash never answers] → `recycle` always
  calls back; if a run ever showed it did not, the set would be cleared on the
  next watcher reload of the parent, which is the state today.
- [The watcher reloads while the set is non-empty] → `rows(under:)` filters
  on every walk, so a reload during the trash's time draws the same tree.
- [Undo restores a file whose row is still marked doomed] → the completion
  clears the mark before the undo is recorded, and `takeBack` runs after.
- [Two trashes in flight] → the set is a union; each completion removes its
  own URLs.

*Open:* whether to switch to `FileManager.trashItem` on a background queue
for the trash itself. It answers with the same original-to-trash pairs and is
in-process. Not needed once the row goes at once; worth measuring if a folder
trash still feels slow after this.
