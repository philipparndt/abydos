## Why

Collapsing a merge on the log page leaves the lanes of the branch it brought in
still drawn on the rows below, with nothing above them: in the report's second
screenshot a green lane and a pink one run down the graph starting from no
commit at all. Reported on 2026-09-01, with a before and after of the same
window — "the green and purple lanes start in the nowhere".

The mechanism is in `HistoryPane.rebuild`, and it is one line out of order:

    graph = GitGraph.lay(out: commits.map { ... })      // every commit
    ...
    visible = zip(commits, graph)
        .filter { !hiddenByCollapse.contains($0.0.hash) }

The layout is computed over **all** the commits and the rows are filtered
afterwards. So every surviving row keeps the `GitGraph.Place` it was given while
the hidden commits were still there — including the lanes that pass through it
on their way to and from commits that are no longer drawn. The lane is real in
the layout and has no visible origin, which is exactly what a line starting in
nowhere is.

Folding is meant to say *this branch came in here and you do not need to see
it*. Drawing its lanes anyway says the opposite, and says it in the one place a
reader is trying to follow a line with their eye.

There is no originating `.abydos/backlog` item: this comes from a direct report,
2026-09-01, with two screenshots.

## What Changes

- The graph is laid out over the commits that will be **drawn**, not over all
  of them and filtered after. A collapsed merge's side branch is gone from the
  input, so its lanes are never assigned and cannot be drawn.
- The merge row itself keeps saying what it hides — the count and the fold
  control are unchanged; this is about the lines, not the affordance.
- `collapsible` and `mergedHashes` are unchanged: deciding *what* a fold hides
  is already right, and is what the new input is built from.

## Capabilities

### Modified Capabilities

- `git-log-page-tree`: gains a requirement that a folded merge's lanes are not
  drawn, which no existing requirement states — the spec covers what folding
  hides in rows and is silent about the graph beside them.

## Impact

- **AbydosKit**: `GitGraph.lay(out:)` is unchanged and is simply given a
  shorter list. The parents of a collapsed merge need care: the merge keeps its
  first parent, which is still drawn, and its second points into commits that
  are not — so the node handed in has the hidden parents dropped, or the layout
  will reserve a lane for a commit it never reaches.
- **AbydosApp**: `HistoryPane.rebuild` computes `visible` first and lays out
  from it; `rebuildFadedLanes` already walks `visible` and is unaffected.
- **Tests**: `GitGraphTests` already builds fixtures with merges; the claim —
  no lane in the output belongs to a commit that is not in the input — is a
  unit test and does not need a window.
- **Cost**: one layout instead of one layout, over fewer nodes.
