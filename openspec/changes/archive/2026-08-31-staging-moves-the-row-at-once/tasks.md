## 1. Measure first

- [x] 1.1 `StallWatch.mark("stage")` around `ChangesPane.activate`/`stageSelected` and `mark("changes reload")` around `reload()`, plus timestamps in `runAcrossOwners` (task created → add returned → status returned → reload done), so every later task's effect is two log lines
- [x] 1.2 Drive a stage on a scratch repository shaped like the report (a dozen changes, opened untracked directories, a fat ignored build directory) and record the baseline timings

## 2. Stop the rediscovery

- [x] 2.1 `Project.loadGit()` reuses the existing `GitRepository` when the discovered git root is unchanged, rediscovering only when the checkout appeared, vanished or moved
- [x] 2.2 A test proving the actor survives a watcher-shaped reload and its ignore fingerprint with it: after a stage-like index write, `needsIgnoredRefresh()` is false; after writing a `.gitignore`, true
- [x] 2.3 Re-drive the baseline: the post-stage `git status --ignored` line is gone from the log

## 3. The row moves at once

- [x] 3.1 On exit 0 in `ChangesPane`, amend the model — move the operation's paths between sides — and rebuild once, before the status re-read replaces the model as today
- [x] 3.2 Replace `refresh()`'s `guard !isBusy … return` with the navigator's kept-refresh shape (`wantsAnother`), and run the kept refresh when the operation ends
- [x] 3.3 Drive it: stage a file and read the trees between add-returned and status-returned — the row is already on the staged side; stage again mid-flight and the second click is not lost

## 4. The refresh sheds weight

- [x] 4.1 Defer the selection-changed diff render by the double-click interval, cancelled by activation or reselection; a driven double-click on a large file stages with no `diff render` mark preceding the stage mark
- [x] 4.2 `EstateChanges.read(after:)` answers the cheap partial for a repository with no submodules, with a test beside the existing estate tests
- [x] 4.3 The second rebuild of a refresh reuses the first's untracked-directory listings instead of re-running `git status -uall` per opened directory

## 5. Before finishing

- [x] 5.1 Compared, on the scratch fixture at load 21–24: ignored walks per session-with-one-stage 4 → 1 (none after a stage; an edited `.gitignore` still walks); STAGE-TIMING command 88→72 ms, status 105→108 ms, reload 4 ms — and the row now moves at the command's return, before the status, with `OPTIMISTIC` printing ahead of `STAGE-TIMING` in the driven log. On the reported repository the eliminated per-stage walk alone was the measured 0.8–1.6 s. Driving also found and fixed a pre-existing loss: two rapid stages raced git's index.lock and one silently failed — operations now chain
- [x] 5.2 `make warnings` clean; `make test`: all new suites green, one full run green earlier in the session; at load 30–41 (other agents on the machine) each later full run flaked a different pre-existing timing-bound test (ToolProcess 60 s bound at 72 s, LSP 30 s at 36 s), every one green alone — the situation the house timing rules name
- [x] 5.3 No `.abydos/backlog/spec/*.md` file is made untrue: nothing recorded staging's responsiveness; the delta in this change is its first account
