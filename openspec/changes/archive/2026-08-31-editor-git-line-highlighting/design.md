## Context

Every piece this feature needs already exists, unconnected. `GitWorkingCopy.diff(for:staged:in:)` runs `git diff --no-color` for one path and `GitPatch.parse` turns it into hunks whose `newStart` and per-line kinds name exactly the line numbers this feature must mark. On the view side, `CodeView` draws its own gutter (`drawGutter`) with a proven pattern for a git-derived, per-line column: blame. Breakpoints already demonstrate how per-line state stays aligned while somebody types (`onLinesChanged`), and `RepositoryWatcher` already tells the window when HEAD or the index moved (`.abydosRepositoryChanged`). What is missing is one AbydosKit type that maps a patch to line marks, one `CodeView` column that draws them, and the wiring that decides when to recompute.

## Goals / Non-Goals

**Goals:**

- Lines added or modified since HEAD carry a coloured bar in the gutter; a deletion leaves a boundary mark under the line it happened after.
- The mapping from a diff to marks lives in AbydosKit and is tested against literal `git diff` output, without a window.
- Marks stay visually aligned during unsaved edits, and become authoritative again on save, reload, and repository change.
- The cost model is explicit: one async `git diff` per file per trigger, nothing per keystroke, nothing per frame beyond drawing rectangles for visible rows.

**Non-Goals:**

- No click action on a mark (no popover showing the old lines, no revert-hunk). That is a follow-up once the marks exist.
- No marks for untracked or ignored files, and no attempt to mark a file in a repository the project has not loaded.
- No new theme keys and no settings toggle in this change — the marks are always on, like line numbers. A toggle can come the day somebody wants one, the way blame got one.
- No change to the row paint order: the marks are gutter-only, so the editor spec's "a row states its precedence in the order it is painted" requirement is untouched.

## Decisions

### Diff against HEAD, in one question

The marks answer "what differs from the last commit", so the diff is taken against HEAD — staged and unstaged together — rather than against the index. `GitWorkingCopy.diff(for:staged:in:)` today asks two separate questions (`git diff` and `git diff --cached`); a small variant that passes `HEAD` as the base gives the combined answer in one child process. Ruled out: calling the existing method twice and merging patches in Swift — merging two hunk lists whose line numbers disagree (the staged patch is numbered against the index) is precisely the bookkeeping git already does correctly, and doing it twice doubles the process cost per trigger.

### Classification lives in AbydosKit: `GitChangedLines`

A new type parses no diffs itself — it walks an existing `GitPatch` and yields, per new-file line number: `.added`, `.modified`, or a set of line numbers after which lines were `.deletedAfter`. A hunk's paired removals and additions (a removal run immediately followed by an addition run) classify the additions as modifications, matching what every other editor calls "changed" rather than "new". Ruled out: classifying in `CodeView` — view code is untestable here, and `GitPatchTests` shows exactly how this type gets tested with literal diff text. Ruled out: reusing `GitLineCounts` — it counts, it does not locate.

### Disk is the baseline; edits shift marks, saves recompute them

The diff is taken against what is on disk. While the buffer is dirty, marks below an edit shift with `onLinesChanged` (the breakpoint pattern), and the lines an edit touched are marked `.modified` locally so typing gives immediate feedback; the next save, external reload, or repository change replaces the whole answer with a fresh diff. Ruled out: diffing the live buffer via `git diff --no-index` against a temp file per debounce tick — a child process per pause-in-typing is the per-keystroke cost the house rules exist to prevent, for marks that are anyway replaced on save. Ruled out: waiting for save with no local shifting — marks visibly pointing at the wrong lines while typing is worse than no marks.

### Recompute triggers and debounce

Recompute on: tab opened, file saved (`told(_:wasSaved:)` and the autosave path), file reloaded from disk, and `.abydosRepositoryChanged`. The repository-change trigger is debounced and applies only to open tabs, following `DebugCoordinator.scheduleAnchoring`'s shape — a checkout that changes a hundred files must not launch a hundred simultaneous `git diff` processes; open tabs are the only ones anybody can see. The diff runs on a background task; the result lands on the main thread into `codeView.setChangedLines(_:)`.

### Drawing: a bar in the gutter, beside the line numbers

A 3 pt vertical bar per marked visible row, drawn in `drawGutter` in a fixed slot between the line-number column and the fold column, so it neither moves when blame toggles nor collides with the breakpoint column on the far left. Deleted-after is a short horizontal wedge at the row's bottom edge in the same slot. Colours are the scheme's existing `gitAdded` (added), `gitModified` (modified) and `gitConflict` (deleted) — read on the main thread only, per the theme-access rule. `gutterZone(at:scrollX:)` learns nothing new: the slot is not clickable in this change.

### Untracked files show nothing

`GitFileStatus` already knows untracked and ignored; both short-circuit to no marks before any diff runs. A wholly-new file with every line green is a gutter shouting nothing.

## Risks / Trade-offs

- [Marks are stale between keystroke and save for edits that merge or split hunks] → acceptable: the local `.modified` marking is an approximation by design, corrected at the next save; breakpoints live with the same approximation and nobody minds.
- [A very large file makes `git diff` slow] → the diff is async and per-file; a result arriving after the tab closed or after a newer trigger is dropped by generation count, the pattern `anchoringWork` uses.
- [Renamed files diff as delete-plus-add] → the diff is asked per current path; after `git mv`, HEAD has no blob at the new path and git reports the file as fully added. Mitigation deferred: rename detection (`-M`) can be added to the diff invocation if it annoys anybody; the failure mode is over-marking, not a crash.
- [The gutter gains a fourth column and pixel arithmetic in `drawGutter` is dense] → the slot is a constant beside `foldColumnWidth`, added where `blameWidth` already proved the layout can take a variable column.

## Open Questions

- Whether the driven-run screenshot harness needs a `--changed-lines` assertion hook for verifying alignment (the way `setBreakpointForTesting` exists) is left to implementation: add it only if the manual screenshot check proves too coarse.
