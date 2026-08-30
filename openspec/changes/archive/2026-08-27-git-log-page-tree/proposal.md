## Why

A commit touching thirty files across six modules is thirty rows in the log
page's changes list, in path order, with no shape. The sidebar has grouped
changes by folder since it was written; the page — which is the one with room —
has not. And a list opened to look through has to be walked a row at a time:
every outline of this kind answers `*` by opening all of it, and this one has
nothing to answer with.

This was proposed as two lines of `git-changes-detail` and pulled out of it
before being built, because that proposal was wrong about where it was starting
from. It said the page "builds its file list itself today" and that a toggle
would point it at `GitChangeTree.build`. In fact `HistoryPane.fileTable` is a
flat `NSTableView` over `[GitCommitFile]`, sharing one data-source extension with
the commit table beside it. There is no tree to re-point: the list has to become
an outline first, and that is a change to the pane the log and the commit page
are both made of.

## What Changes

- The log page's changes view SHALL become an outline, and SHALL offer both a
  flat list of files and a folder tree. The flat arrangement is what it draws
  today, row for row.
- The choice SHALL be remembered between sessions, like the other view
  preferences.
- `*` SHALL expand the whole tree from any row in it.
- The selection SHALL survive a change of arrangement, and the row it lands on
  SHALL be the same file.

## Capabilities

### New Capabilities
- `git-log-page-tree`: how the log page arranges the files of one commit, and the
  keys that open them.

### Modified Capabilities

None. `openspec/specs/git-pages` says the log is a page in the editor area, that
the commit view is the same page in another tense, and that a commit is an object
with verbs. It says nothing about how the files inside it are arranged.

## Impact

- `HistoryPane` — the file list becomes an `NSOutlineView`; the shared
  data-source extension has to tell the two views apart; selection moves from a
  row index into `[GitCommitFile]` to a path.
- `GitChangeTree` — no change. `build` already makes the shape, and
  `git-changes-detail` gave its nodes the line counts these rows will carry.
- `Settings` — one boolean, beside the other view preferences.

**The risk is the pane, not the feature.** `HistoryPane` is 1,551 lines and is
both tenses of the git page; its file list is wired to the diff view, to
`onSelectFile`, and to the column arrangement that hands a diff to the editor
area instead. Everything here is reversible and none of it is subtle, but it is
surgery on something central rather than an addition at the edge.
