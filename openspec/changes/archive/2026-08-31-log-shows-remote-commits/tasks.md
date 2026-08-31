## 1. The union and the remote-only set (AbydosKit)

- [x] 1.1 Let `GitHistory.log` take the upstream alongside the revision, passing both tips to one `git log` so git orders the union; a nil upstream leaves today's behaviour untouched
- [x] 1.2 Add `GitHistory.remoteOnly(of:in:)`: resolve the ref's upstream via `for-each-ref %(upstream:short)` (as `GitPush` does), then `rev-list <ref>..<upstream>`; no upstream means an empty set
- [x] 1.3 Tests in `GitHistoryTests` on the clone-as-remote fixture: a behind branch's scoped log contains the unpulled commit, a branch with no upstream lists only its own ancestry, a diverged pair reports exactly the upstream-only hashes as remote-only, and the union window still pages with skip and limit
- [x] 1.4 A `GitGraphTests` claim for the two shapes, named as sentences: fed a fast-forward union the remote commits share the lane; fed a divergence they take a lane that joins at the common ancestor

## 2. The page (AbydosApp)

- [x] 2.1 `HistoryPane.reload()` asks for the upstream union when `scopedRef` is set and keeps `remoteOnly: Set<String>` beside `unpushed`
- [x] 2.2 Fix `loadMore()` to pass `revision:` (and the upstream) so paging keeps the scope instead of falling through to the everything-log
- [x] 2.3 `CommitRowView` gains `isRemoteOnly`, applied as one alpha (the refs tree's merged-branch 0.45) over subject, meta, author, dot and lane strokes — the ref pills exempt
- [x] 2.4 `pageReportForTesting()` marks remote-only rows in the per-row line, so the driver can read what is dimmed

## 3. Proving it on the page

- [x] 3.1 Drive the app against a scratch clone that is behind, report the log page, and check the unpulled commit is present, marked remote-only, and on the expected lane; repeat for a diverged clone
- [x] 3.2 Screenshot the diverged case for the change, dimmed rows and full-strength `origin/…` chip visible

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: nothing there constrains which commits the scoped log lists; the delta in this change is the first account of it
