## Measured

A scratch superproject of 60 submodules, one of them 4,003 files, opened with
the changes pane up; `git worktree add` and `remove --force` of that submodule
under `repos/` in a loop for 30 s. Load 7–11, Apple silicon, release build.

| | before | after |
|---|---|---|
| Abydos processor over the burst | 84 % | 41 % |
| `git` processes it started | ≥ 7,340 | ≥ 660 |

The processor figure is the app's own; the `git` it starts is not in it, which
is why the second row is the larger saving.

## Decisions

**Fold at the source, not later.** `PendingChange` is one value on the watcher's
queue; the first batch schedules a delivery and the rest merge into it. Nothing
waits that did not wait before, and every user of `FileSystemWatcher` gets it.

**`rescanned` beside `directories`.** A batch can name some files and only say
"scan" for others, and `directories` holds the parents of both. Attributing the
parent of a named file as a scan would make a file saved at the root a question
about the whole project, so the scan directories are carried on their own.

**One settler, leading edge.** The navigator owns it and hands the folded change
to the changes pane through `onFilesSettled`, so the colours and the list agree
on when a burst ended. Quiet 0.6 s, cap 3 s. Without the leading edge every save
would have reached the changes pane 0.6 s later than it did.

**What stays immediate.** Re-listing open directories, the palette's index, the
file-kind flag, reloading an open file and the run configurations. The re-list
is followed by a whole `reloadData()` and a restore of folds, selection and
scroll, which is not free with many rows open; folding at the source bounds it
to one per main-thread turnaround, and the measurement above includes it.

**Asked-for refreshes never wait.** The header's refresh, a commit, a checkout,
the repository watcher: all call `refreshGitStatus` or `refresh()` directly.
A changes-pane read asked for while one runs now waits for it rather than
running beside it, and is folded into one.
