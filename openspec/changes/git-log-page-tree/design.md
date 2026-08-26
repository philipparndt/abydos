## Context

`HistoryPane` is both tenses of the git page — the log in a 300 pt sidebar
column, and the commit page in the editor area — and its changes view is
`fileTable: HistoryTableView`, a flat `NSTableView` whose rows are indices into
`files: [GitCommitFile]`. One extension conforms the pane to
`NSTableViewDataSource` for *both* tables and tells them apart with
`tableView === commitTable`. Selecting a row reads `fileTable.selectedRow`,
indexes `files`, and either hands the file to `onSelectFile` (the column, which
has nowhere to put a diff) or loads the diff into `diffView` (the page, which
does).

`GitChangeTree.build` already produces the folder shape from `[GitChange]`, and
since `git-changes-detail` its nodes carry `lines`, so the counts come along.

## Goals / Non-Goals

**Goals:**

- Both arrangements, from one view.
- The flat arrangement identical to today's, row for row.
- Selection by path, so it survives the switch.
- `*`, in the view that now has something to open.

**Non-Goals:**

- The commit table. It is a list of commits and has no folders.
- A flat arrangement for the *sidebar's* changes tree. Nobody has asked for one,
  and the preference here is about this view.
- Collapsing single-child folder chains. `GitChangeTree` deliberately does not,
  and its comment says why; this view inherits that decision rather than
  reopening it.

## Decisions

### The view becomes an outline in both arrangements

Not "a table for files and an outline for folders". Two views means two
data sources, two selection paths and two sets of row-view code, and the flat
arrangement would be the one nobody exercised after the first week.

An `NSOutlineView` with no folders draws exactly the rows a table does, so the
flat arrangement is the same outline over a list of childless nodes. What the
preference changes is the shape handed to it, not the view.

`NSOutlineView` is an `NSTableView`, so the existing extension keeps working for
`commitTable`: AppKit asks an outline its own questions. What has to be watched
is the delegate methods the two share — `heightOfRow`, `rowViewForRow` — which
are already written to answer for either.

### The rows are `GitChangeNode`, and selection is a path

`[GitCommitFile]` stays the source of truth, mapped to `[GitChange]` to build the
tree. A node knows its path; a path finds its file. Every selection, restore and
reveal in this view goes through the path.

Rejected: keeping the row index and translating. The two arrangements put a file
at different depths and different indices, so an index means a different file
after a toggle — which is worse than losing the selection, because it looks like
it worked.

### `*` walks rows, from the top

`NSOutlineView` has no expand-all, and expanding row by row while re-reading
`numberOfRows` is what the rest of this repository does. From the top rather
than from the selection down, because `*` means "all of it" everywhere else it
appears.

Rejected: recursing the node tree calling `expandItem` on each — it visits nodes
the view has never been handed, which is the shape of bug the project view's
compaction change spent its time on.

### The toggle is a preference, in the page's own header

A `Settings` boolean beside the other view preferences, so the next commit is
arranged the way the last one was. The control goes where the page's other
controls are; in the 300 pt column arrangement there is no room for it, and the
column hands its diffs away anyway — so the sidebar tense keeps the flat list
and the preference governs the page.

## Risks / Trade-offs

- **Surgery on a central pane.** 1,551 lines, both tenses, wired to the diff view
  and to `onSelectFile`. → The flat arrangement is the control: if it draws and
  selects exactly as before, the conversion is sound, and that is one driven
  comparison rather than an argument.

- **The shared data-source extension.** An outline and a table answering through
  one object is legal and is a trap: a method meant for one that the other also
  asks. → The three shared delegate methods are read before the change and left
  answering for both; the data-source methods are separate protocols and cannot
  collide.

- **A commit of three files gains folders it does not need.** `GitChangeTree`
  does not collapse chains, so `Sources/AbydosKit/Git/GitBlame.swift` alone is
  four rows where the flat list had one. → Which is why both arrangements exist
  and why the flat one is the default.

### The page only, and the code says so

The column tense does not get the folder arrangement. It is 300 pt wide and hands
its diffs to the editor area, so four rows of `Sources/AbydosKit/Git` to show one
file is most of its width spent on indent. `rebuildFileRows` asks for folders
only when `arrangement == .page`, so the decision is in the code rather than in a
comment, and the preference is named for commit files — which is the page's list.

### The control is a segmented pair in the strip above, not a header

There is nowhere to put a header. The page's changes view is a pane of a split
whose own comment records what happened the last time something other than a
scroll view went in one: a stack inside a split gave autolayout a size it could
satisfy two ways, the terminal panel below flickered once per frame, and the
divider could not be dragged. The strip above the split is a plain container that
already holds the Changes/Message tabs, so the toggle sits at its far end.

A View-menu item exists as well, and the two keep each other in step. The menu
item alone was the first attempt and it was wrong: a menu item is not a toggle,
and nothing on screen said which arrangement was in force.

## Open Questions

None. The one above is decided in `Decisions`.
