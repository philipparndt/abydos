## Context

"Log · main" is `SidebarController.showLogPage(scopedTo:)` → `HistoryPane.setRef` → `GitHistory.log(revision: "main")`, which passes the one revision to `git log` and therefore lists only that branch's ancestry. The machinery for everything else already exists: `GitGraph.lay(out:)` assigns lanes from parentage alone and is well tested; `GitHistory.unpushed` already computes "hashes on one side and not the other" (`HEAD --not --remotes`) and `HistoryPane` already carries that set per row (`isUnpushed`); `GitPush` and `GitBranches` already resolve upstreams via `for-each-ref %(upstream:short)`; and `BranchesPane` already established how a row is dimmed (an alpha over what the row would have said, not a new grey). The change is to put the upstream's commits into the list, and the remote-only set onto the rows.

## Goals / Non-Goals

**Goals:**

- A ref-scoped log whose ref has an upstream shows the union of both
  ancestries, ordered by git, laid out by the existing lane algorithm.
- Remote-only rows are dimmed, their explaining `origin/…` chip is not.
- The behind/ahead discrimination is visible in the graph for free: same lane
  when the upstream is a fast-forward ahead, a second lane where diverged.
- Paging keeps the scope (fixing the existing `loadMore()` fault rather than
  copying it into a second path).

**Non-Goals:**

- No change to the unscoped log: `--all` already includes remote refs, and
  dimming there would need a notion of "remote-only relative to what?" that
  the everything-log does not have. If somebody wants it later, it is its own
  question.
- No pull/fetch verbs on the page and no "behind by N" header — the sidebar
  and estate page already say that; this change makes the log stop
  contradicting them.
- No new fetch: the page shows what the last fetch brought, exactly as the
  behind counts do (`git-remote-traffic` owns when that is re-read).

## Decisions

### One `git log <ref> <upstream>`, not two logs merged in Swift

`GitHistory.log` gains the ability to take the upstream alongside the
revision, so git itself merges, orders and windows the union — the same
choice `--all` already embodies in the unscoped case. Ruled out: a second
`log` call for `<ref>..<upstream>` merged into the array by date — interleaving
two windows correctly (skip/limit across two streams, ties in dates) is
bookkeeping git does natively, and the fold-by-merge feature needs one
consistent parent-closed list for `GitGraph` anyway. Ruled out: switching the
scoped log to `--all` and filtering — that loads every branch to show two.

### The remote-only set mirrors `unpushed`

A new `GitHistory.remoteOnly(of ref:in:)` resolves the upstream
(`%(upstream:short)`; absent upstream → empty set, log unchanged) and runs
`rev-list <ref>..<upstream>`, returning the hashes plus the upstream name.
`HistoryPane` stores it beside `unpushed` and passes `isRemoteOnly` into each
row, exactly as `isUnpushed` travels today. Ruled out: deriving remote-only in
the view from the ref chips — only the tip carries a chip; the commits behind
it carry nothing that names their side.

### Lanes come from parentage, unchanged

`GitGraph.lay(out:)` is not modified. Fed the union, the fast-forward case
puts the upstream's extra commits above the local tip on the same lane
(they are its descendants on the first-parent line), and the diverged case
opens a lane at the fork — which is exactly the same-branch-or-separate-branch
rendering the request describes, decided by "the changeset they are built on"
because that is all the layout ever looks at. Ruled out: a dedicated
"remote lane" pinned to the right — it would disagree with the layout the
unscoped log draws for the same commits.

### Dimming is an alpha, the chip is exempt

`CommitRowView` applies one alpha (the refs tree's merged-branch 0.45) to the
subject, meta line, unpushed glyph, author column, dot and the row's graph
strokes when `isRemoteOnly`. The ref pills keep full strength: the
`origin/main` chip is the reason the row is on the page, and the refs-tree
precedent is explicit that the reason mark is not dimmed with the rest.
Ruled out: a fixed grey — `BranchesPane`'s own comment records why ("a fourth
meaning for a row's colour"); an alpha keeps whatever the row already said and
says it quietly. Where lanes are not drawn at all (a search, a path scope),
the text dimming alone still marks the rows.

### Selection and verbs treat a remote commit as a commit

A dimmed row opens on click like any other — its diff, its files — because it
is a real commit somebody may want to read before pulling. Verbs that assume
the commit is in the branch's own history (interactive-rebase-shaped things,
if the menu grows them) are out of scope here; today's menu is inspection and
copying, which remote commits support as well as local ones.

## Risks / Trade-offs

- [`git log <ref> <upstream>` changes row order for the ahead case: unpushed
  local commits and newer remote commits interleave by topology] → that is the
  truthful order (it is what the unscoped log already shows), and the dimming
  plus chips make the two sides tellable apart.
- [A very stale upstream adds hundreds of behind-commits to the first page]
  → the existing `pageSize` window applies to the union; the page fills with
  what is newest, which is the right answer for "what would a pull bring".
- [`%(upstream:track)` counting and this page can disagree just after a fetch
  elsewhere] → both read the same refs; the page reloads on the same
  repository-changed signal the sidebar counts do.
- [Dimming plus lane colours at low alpha may fall under contrast on some
  schemes] → the alpha rides on top of theme colours as the refs tree's does;
  if a scheme proves unreadable the alpha is one constant to tune.

## Open Questions

- Whether the remote-only rows should also appear in a *path-scoped* log
  (`--follow -- <path>`), where no graph is drawn and `--follow` with two
  revisions is murkier git territory, is left open; the change targets the
  ref-scoped log and leaves the path-scoped one as it is until somebody asks.
