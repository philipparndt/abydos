## 1. The diff and its classification (AbydosKit)

- [x] 1.1 Give `GitWorkingCopy` a diff against HEAD for one path — staged and unstaged in one answer — beside the existing `diff(for:staged:in:)`, short-circuiting to nil for untracked and ignored files via `GitFileStatus`
- [x] 1.2 Add `GitChangedLines`: walk a `GitPatch` into per-line marks (`added`, `modified`, `deletedAfter`), pairing a removal run followed by an addition run into modifications
- [x] 1.3 Tests in `Tests/AbydosKitTests/GitChangedLinesTests.swift` against literal diff text: a replaced line is modified, one-replaced-by-three is three modifieds and no deletion mark, a pure addition is added, a pure removal is a deletion mark after the preceding line, an empty diff is no marks
- [x] 1.4 A live test beside the parse tests: a temp repository where a committed file is edited, proving the HEAD diff marks staged and unstaged edits alike

## 2. Drawing the marks (AbydosApp)

- [x] 2.1 Give `CodeView` a `setChangedLines(_:)` beside `setBlame`/`setBreakpoints`, storing marks per document line and setting `needsDisplay`
- [x] 2.2 Draw the marks in `drawGutter`: a 3 pt bar per marked visible row in a fixed slot between the line numbers and the fold column, a bottom-edge wedge for deleted-after; colours `gitAdded`, `gitModified`, `gitConflict`, read on the main thread
- [x] 2.3 Shift marks on `onLinesChanged` and mark the touched lines modified locally, the way breakpoints stay anchored

## 3. Wiring the recomputes

- [x] 3.1 Compute marks in `EditorViewController` when a tab opens, when a file is saved (both `told(_:wasSaved:)` and autosave), and when a file reloads from disk — async, with a generation count so a stale result is dropped
- [x] 3.2 Refresh the open tabs' marks on `.abydosRepositoryChanged`, debounced following `DebugCoordinator.scheduleAnchoring`'s shape
- [x] 3.3 Drive the app against a scratch copy of a repository and screenshot an open file with an edit, an insertion, and a deletion, proving the marks sit beside the right lines

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: the gutter's change marks were unspecified before this change, and the new `editor-change-marks` spec in this change is their first account
