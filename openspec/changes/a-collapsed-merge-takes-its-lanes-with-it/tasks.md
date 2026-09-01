## 1. One list, one layout

- [x] 1.1 Done differently, and the design says why: the whole history goes in with a `hidden` set, because a filtered list stops the merge being a merge.
- [x] 1.2 Not dropped — named. `GitGraph.lay(out:hidden:)` opens no lane for a hidden parent and lets a hidden commit take no part in the walk, which was the second half of it.
- [x] 1.3 Checked: `rebuildFadedLanes` walks `visible` and reads each row's own graph, so it is consistent with whatever the layout produced by construction. No change needed, and now said rather than assumed.

## 2. Proving it

- [x] 2.1 Two, against the real API: a folded branch leaves no lane behind, the merge still offers to unfold, and unfolding gives the same picture back.
- [x] 2.2 Driven on a scratch repository with a real merge. The page report gained `dangling=` — lines drawn on a row that nothing above it hands down — and the count was checked against the *old* code first: `dangling=1` before the fix and `0` after, so the measurement has teeth rather than reading zero because it always would. Fold 9 → 6 rows, unfold 6 → 9, dangling 0 throughout.

## 3. Finishing

- [x] 3.1 `make test` and `make warnings`, both clean, both by their exit codes: 3981 tests in 511 suites, WARN_EXIT=0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
