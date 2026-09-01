## Why

Expanding the selected folder in the commit page's changes tree with → loses the
selection: the row is open afterwards and nothing is highlighted, so the next
arrow key has nowhere to go from. Reported on 2026-09-01 with a screenshot
before and after — a selected `U` folder row, then the same row expanded with no
selection anywhere in the pane.

The report matters less than the pattern behind it, which the request names:
*we had such issues a lot before*. There are eight `NSOutlineView`s in this app
and each pane has written its own answers to the same four questions — how the
selection survives a rebuild, what the arrow keys do, what happens when the
selected row stops existing, and where the keyboard goes when a row is opened.
`TreeSelection` in AbydosKit is the one piece that *was* extracted, for exactly
this reason, and it covers only the first question. The comments left around the
other three read as three near-copies that have already drifted:
`ProjectNavigatorViewController`, `ChangesPane`/`ChangedFileList` and
`BranchesPane` each hold a selection by path, each restore it after a rebuild,
and each do it slightly differently.

The leading explanation for this particular report, to be confirmed by a driven
run before anything is written: the selection is held **by path**, and a
compacted folder row's path is not stable across a rebuild that changes the
compaction. Expanding `openspec/changes/the-zoom-reaches-every-control` — one
compacted row in the screenshot — un-compacts it, a rebuild follows, and
`select(path:)` looks for a path that is no longer any row's, finds nothing, and
returns without saying so. That is a guess with evidence behind it and not a
diagnosis, and the first task is to make it one or replace it.

There is no originating `.abydos/backlog` item: this comes from a direct report,
2026-09-01, with two screenshots.

Two more reports on the same tree arrived while this was being written, and
both are the same shape:

- **Staging a file loses the selection.** The row moves from `Unstaged` to
  `Staged`, so it stops existing where it was, and nothing lands on the
  neighbour above or below. `ChangesPane` already computes exactly that
  fallback — `TreeSelection.surviving`, the function the navigator uses when
  rows are deleted — and does not apply it here.
- **That tree draws AppKit's selection, not the app's.** The screenshot shows
  the system's full-bleed blue band, where every other tree in this app draws a
  rounded, inset pill through `Theme.selection`, blue with the keyboard and grey
  without it. The navigator does that in `NavigatorRowView.drawSelection(in:)`
  and the changes tree simply has no row view of its own, so AppKit fills in.

That is the fourth question the trees answer separately — *what does a selected
row look like* — and it is the one where the difference is visible in a
screenshot rather than only in a behaviour.

## What Changes

- The selection survives expanding and collapsing a row, in every tree — which
  is the first report.
- The selection survives a row moving out from under it: staging a file lands
  the selection on the neighbour, through the fallback the pane already
  computes and does not use.
- Every tree draws the app's selection — the rounded inset pill, blue with the
  keyboard and grey without — rather than leaving AppKit to paint its own band
  where a pane forgot to say.
- A tree behaviour is extracted into the control library that
  `the-zoom-reaches-every-control` introduces, so the four questions above have
  one answer rather than three: holding a selection across a rebuild, the arrow
  keys, what a lost selection falls back to, and where the keyboard goes.
- `TreeSelection` stays where it is and keeps its callers. It is the arithmetic;
  the new piece is the behaviour around it, which is what has been copied.
- **A restore that finds nothing says so** rather than returning silently. The
  present code returns early from `select(path:)` when the path has gone, which
  is exactly how this report looks from the inside: nothing failed, nothing was
  logged, and the selection simply was not there any more.
- The project tree, the changes tree, the branches tree and the pull-request
  file tree move onto it. The other four outlines — settings, the debugger's
  variables, the structure pane, the variable popup — are named as out of scope
  and swept later.

## Capabilities

### New Capabilities

- `tree-behaviour`: what every tree in this app does with a selection, the
  arrow keys, a rebuild, and a row that stops existing.

### Modified Capabilities

- `version-control`: the changes tree gains the requirement that expanding a
  row keeps the selection, which is the report.

## Impact

- **AbydosApp**: a tree behaviour in `Controls/`, and four panes moved onto it
  at their outline construction sites and their key handling.
- **AbydosKit**: `TreeSelection` unchanged. Any new arithmetic — a stable
  identity for a compacted row, if that is what the run says — lives beside it
  and is tested there.
- **Risk**: four panes' keyboard behaviour is four panes' worth of muscle
  memory. Each one moves in its own commit with a driven capture of its key
  behaviour before and after, so a difference is visible rather than discovered.
- **Depends on** `the-zoom-reaches-every-control`, which creates the library
  this lives in.
