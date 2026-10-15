## Why

The maintainer, 2026-10-15, with a board of implementation briefs: an agent
adding and removing git worktrees inside a superproject of ~190 submodules held
Abydos at 250–530 % processor for as long as it ran, with ~46 of 94 threads
busy and `fseventsd` at 36 %.

Reading the code against the briefs found three causes, one of which they did
not name:

- **The changes pane's attribution was the wrong way round.**
  `EstateChanges.read(after:)` returned "everything" for every batch whose paths
  FSEvents had all named — every saved file swept every repository — and sent
  the batches it could *not* enumerate, whose path list is empty, to nothing.
  The submodules spec's scenario "a file is saved in one submodule" has never
  held. It was so from the type's first commit, and a later fix to the same
  guard kept the inversion.
- **Every FSEvents batch was a full round of work on the main thread**: one
  delivery per batch, each running the tree, a `git status`, the dependency
  check and the changes pane, whether or not the main thread had kept up.
- **The changes pane started a read per refresh**, with nothing stopping a
  second before the first finished — so during a burst, sweeps of every
  submodule ran on top of each other, a dozen `git status` each.

## What changes

- The attribution reads the flag the right way round, and a batch FSEvents could
  not enumerate is attributed by the directories it said to scan: the submodule
  a directory is in, every submodule under it, the superproject when it is in
  none. Only the project root itself is a reason to read everything.
- The watcher delivers at most one batch at a time to the main queue; batches
  arriving meanwhile are folded into it.
- The work that costs a `git status` or more — the tree's colours, the
  dependency check, the changes pane — runs once a burst settles, or every three
  seconds while it lasts. The first event after a quiet spell runs at once, so a
  single save is as quick as before. The tree's rows stay immediate.
- The changes pane reads one estate at a time, folding what is asked for
  meanwhile into one read after it.

- The repository watcher, over the git directory, says which directories moved,
  and the changes pane attributes them as the submodules spec already requires:
  `modules/svc-47/…` is `svc-47`, a ref of the superproject's is the
  superproject, the index or the git directory itself is everything. Until now
  `GitEstateRefresh.work(forChangedDirectories:)` was tested and never called,
  and every event outside the object store swept every repository. The
  watcher's 0.4 s wait for quiet gains the same 3 s cap, so a loop that never
  goes quiet still delivers.
