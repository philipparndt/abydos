## 1. Name it

- [x] 1.1 Two tree steps: `end` scrolls to the last row, `place` prints the clip's offset, the top row's key and the visible rows.
- [x] 1.2 Driven, before the fix: `end,place,reload,place` on a tree longer than its pane. **The second line was not at the top**: `y=2237 top=dir092` both times, and the same for a watcher event, an open file rewritten, a session event with the root collapsed and expanded, and a selection restored out of view. The table is in the design; the reported jump did not reproduce in any rebuild a run can trigger.

## 2. Fix it

- [x] 2.1 `rememberPlace()` and `restore(place:)`: the top visible row by the keys `expandedPaths()` uses, its offset within the row, and the pixel offset as the fallback, clamped.
- [x] 2.2 Both calls in each of the six rebuilds: the watched-directory reload, `applySettings`, `reloadTreeMarked`, `show(_:)` for the sessions, `rebuildDependencies`, and `redrawRows` after a rename or trash.

## 3. Proving it

- [x] 3.1 Driven, after the fix: the same run prints the same top row and offset on both lines — which it did before as well, so the fix is a no-op where the place was kept and a fix only where a rebuild shortens the tree for a moment.
- [ ] 3.2 Driven, the reported case: a `--claude-running` event at a few seconds, with the tree scrolled first; the place printed before and after is the same. **Half done.** The event with the sessions root collapsed and expanded keeps the place, before and after the fix. The session's *files* changing while their folder is open — the rows the reporter was reading — could not be driven: the files never appeared under the session row in a driven run. Open, with the two questions for the reporter in the design.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4371 tests in 557 suites, exit 0, load 40 at the end of the run. `make warnings` first failed: the tree step was called `scroll` and shadowed the editor's step of that name, which the sweep reported as an unreachable pattern; renamed `place`, and the sweep exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `project-view` spec is what
this change adds to.
