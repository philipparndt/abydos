## Why

A file open in the editor says nothing about what git thinks of it. The gutter
can name who last touched each line (blame), yet the question asked far more
often — *which of these lines have I changed since HEAD?* — has no answer short
of opening the commit page or running `git diff` in a terminal, and then mapping
hunk numbers back to the window by hand. Every other editor on the machine draws
change marks in the gutter; theirs going missing here is noticed daily.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-08-31 — "currently open files do not highlight the changed lines
in git. This shall be changed."

## What Changes

- Open files gain per-line change marks against HEAD: a coloured bar in the
  gutter beside lines that are added or modified, and a boundary mark where
  lines were deleted.
- The marks are computed in AbydosKit from the diff machinery that already
  exists (`GitWorkingCopy.diff` → `GitPatch`), so the mapping from hunks to
  line numbers is testable without a window.
- The marks stay aligned while somebody types — anchored the way breakpoints
  are — and are recomputed when the file is saved, reloaded from disk, or the
  repository changes underneath it (commit, checkout, stage).
- Files that are untracked, ignored, or outside any repository show no marks:
  a file that is entirely new would be entirely coloured, which says nothing.
- No behavioural change to blame, breakpoints, line numbers, or the row paint
  order — the marks live in the gutter, not in the row.

## Capabilities

### New Capabilities

- `editor-change-marks`: per-line git change indication in the editor gutter —
  what is marked, against what the difference is taken, how marks survive
  typing, and when they are recomputed.

### Modified Capabilities

<!-- none: the marks are a gutter column, not a row band, so the editor spec's
paint-order requirement is untouched, and no existing requirement changes. -->

## Impact

- **AbydosKit**: a new type turning a `GitPatch` into per-line change kinds
  (added / modified / deleted-after), plus a diff variant against HEAD if the
  existing working-copy diff does not already cover staged-plus-unstaged in one
  answer. New tests beside `GitPatchTests`.
- **AbydosApp**: `CodeView` gains a `setChangedLines(_:)` beside `setBlame` /
  `setBreakpoints`, and `drawGutter` draws the new column;
  `EditorViewController` computes marks on open/save/reload, debounced the way
  `DebugCoordinator` debounces re-anchoring; `MainWindowController` refreshes
  open tabs on `.abydosRepositoryChanged`.
- **Theme**: uses the existing `gitAdded` / `gitModified` / `gitConflict`
  scheme keys; no new key expected.
- **Cost**: one `git diff` per file per save/reload/repo-change, async and
  debounced — never per keystroke.
