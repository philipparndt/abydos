## Why

The log page scoped to a branch shows only that branch's ancestry
(`GitHistory.log` is given the one revision), so the commits its upstream has
and the branch does not are simply absent. The evidence is a screenshot from
2026-08-31: a repository saying "1 behind · 2 ahead" in its own header, and
"Log · main" showing no trace of the one commit `origin/main` is ahead by —
somebody reading the log to decide whether to pull is shown a log that says
there is nothing to pull. Fork, on the same repository, draws that commit
dimmed under an `origin/main` chip, on a lane of its own where the histories
diverged — which is the model the request names.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-08-31, with both screenshots attached.

## What Changes

- The log page scoped to a ref that has an upstream also loads the upstream's
  commits, so what the branch is behind by is on the page.
- Remote-only rows — commits the upstream has and the branch does not — are
  rendered dimmed, the way a merged branch is dimmed in the refs tree: the
  same colours at a quieter alpha, with the `origin/…` chip that explains the
  row left at full strength.
- The graph places them where their parentage puts them: on the branch's own
  lane when the upstream has simply moved ahead (a fast-forward away), on a
  lane of their own where the histories have diverged. The existing lane
  algorithm already does this; the commits only have to be in its input.
- Paging a scoped log keeps its scope: `loadMore()` today drops the
  `revision:` argument and falls through to the everything-log, which the new
  loading path must not repeat, so the fault is fixed rather than inherited.
- The unscoped log (no ref) is unchanged: it already sweeps `--all`.

## Capabilities

### Modified Capabilities

- `git-pages`: the log page gains requirements for what a ref-scoped log
  contains (the ref's ancestry and its upstream's), how remote-only rows are
  rendered, and that paging keeps the scope. Nothing existing in the spec
  constrains the commit list today, so the delta is additions only.

### New Capabilities

<!-- none: the log page already has a spec, and this changes what it shows. -->

## Impact

- **AbydosKit**: `GitHistory.log` learns to take the upstream alongside the
  ref (one `git log <ref> <upstream>` — git merges and orders the union); a
  helper resolves a ref's upstream (`%(upstream:short)`, as `GitPush` and
  `GitBranches` already do) and lists the remote-only hashes (`rev-list
  <ref>..<upstream>`, the mirror of `unpushed`). `GitGraph` is untouched.
- **AbydosApp**: `HistoryPane` keeps a `remoteOnly: Set<String>` beside
  `unpushed`; `CommitRowView` gains the dimming; `loadMore()` gets the
  `revision:` fix. `pageReportForTesting()` says which rows are remote-only,
  so the driver can check it.
- **Tests**: `GitHistoryTests`' clone-as-remote fixture already builds
  behind/diverged repositories; new claims live beside it.
- **Cost**: one extra `rev-list` per reload of a scoped log; nothing per row.
