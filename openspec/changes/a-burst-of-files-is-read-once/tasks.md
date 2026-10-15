## 1. Attribution

- [x] 1.1 `FileSystemChange.rescanned`: the directories FSEvents said to scan
      (MustScanSubDirs, and the root on RootChanged), apart from `directories`.
- [x] 1.2 `GitEstateRefresh.work(for:in:)` and `work(forRescannedDirectories:in:)`:
      named paths as before; a scanned directory makes stale its submodule or
      the superproject and every submodule under it; the root, or an unnamed
      batch that says nowhere, is the inventory.
- [x] 1.3 `EstateChanges.read(after:)` reads through it; the inverted guard is
      gone.
- [x] 1.4 Tests: named batch attributed, scan inside / beside / above
      submodules, nested both ways, root, nowhere said, mixed batch — and
      checked that eight of them fail with the guard inverted again.

## 2. Folding at the source

- [x] 2.1 `FileSystemChange.merge`: unions, `namesEveryPath` ANDed.
- [x] 2.2 `PendingChange` in the watcher: one delivery waiting at a time;
      `stop()` empties it.
- [x] 2.3 Tests: merge, an unnamed batch stays unnamed, three offers deliver as
      one.

## 3. Settling the git work

- [x] 3.1 `Settler`: leading edge, quiet 0.6 s, cap 3 s, given clock and
      scheduler.
- [x] 3.2 Navigator: `refreshGitStatus`, the dependency check and the new
      `onFilesSettled` go through it with the folded change; cancelled on
      close and on a new project.
- [x] 3.3 The changes pane hears `onFilesSettled`, and reads one estate at a
      time with what arrives meanwhile folded into one read.
- [x] 3.4 Tests: a single event runs at once, a short burst once more after
      it, a long one at the cap, cancel forgets.

## 4. Done

- [x] 4.1 Measured before and after on a scratch superproject (design.md).
- [x] 4.2 `make test` and `make warnings` clean.
