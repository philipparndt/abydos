## Context

The traced path from double-click to the row moving: `ChangesOutlineView.mouseDown` → selection change → `SidebarController.showDiff` → `DiffView.setDiff` (inline patch parse plus two tree-sitter parses, on the main thread, 194 ms in the stall log) — and only then the queued stage Task: `GitEstateOperation.stage` → `git add` (~10 ms) → `refresh()` → `GitPush.state` (3–4 processes) → full estate read → two tree rebuilds with one `git status -uall -- dir` per opened untracked directory *per rebuild* → line counts → the navigator recolours the whole project tree. About 0.4 s later FSEvents reports the app's own index write and the entire refresh runs again — and on that path `MainWindowController` calls `Project.loadGit()`, which `discover`s a **new** `GitRepository` actor, discarding `statusCache`, `ignoredCache` and `ignoreRulesFingerprint`, so `needsIgnoredRefresh()` is always true and `git status --ignored` (0.82–1.56 s here) runs after every stage. A refresh arriving while `isBusy` is dropped without retry. 491 of 498 entries in the stall log are `idle` at 0–1% CPU — a main thread waiting, not working, which is why nothing named itself.

## Goals / Non-Goals

**Goals:**

- The staged row switches sides within a frame of `git add` returning.
- The ignored-files walk runs when ignore rules change, not per stage — restoring the invariant the code's own comment states.
- No user action is silently swallowed: a refresh that lands busy runs after.
- A double-click stages without first paying for a diff render.
- The stage path is measurable: stalls in it carry its name.

**Non-Goals:**

- No suppression of the FSEvents echo. The watcher refresh is the net that catches external writers, and FSEvents cannot say who wrote; a "probably my own write" window is a guess about authorship. Once the rediscovery stops, the echo costs one cheap status read plus a rebuild, which coalescing absorbs. If it still shows in the marks afterwards, writer identity is a change of its own.
- No async rewrite of `DiffView.setDiff`; its inline cost is a known, bounded design (5,000-line cap) and a separate subject.
- No change to what staging *means* — sides, folders, discard fencing all stay as specified.

## Decisions

### The watcher reuses the repository it has

`MainWindowController`'s `.git`-event closure calls `Project.loadGit()` today, and `loadGit()` answers with `GitRepository.discover` — a new actor. It becomes reuse: `loadGit()` keeps the existing actor when the discovered git root is unchanged (the repository only needs *rediscovering* when the checkout appeared, vanished or moved), and the actor's caches keep their lifetimes — `ignoreRulesFingerprint` above all, which is the whole point: `needsIgnoredRefresh()` then answers from the fingerprint as designed. Ruled out: copying the fingerprint into the new actor — it saves the one field and still discards the status and ignored caches, and a discover per FSEvents batch is churn with no question behind it. Ruled out: fixing it in the navigator instead — the navigator is one of several listeners; the churn is upstream of all of them.

### The row moves on exit 0, the status confirms

`ChangesPane` applies the operation's outcome to its model as soon as the command returns — the staged paths move between the unstaged and staged sides, the tree rebuilds once from the amended model — and the status re-read that was always going to run lands afterwards and replaces the model wholesale, as it does today. The optimistic step is presentation, not truth: the porcelain status remains the single authority, so a partial failure (one path refused, the rest added) shows briefly optimistic and is corrected by the very next read. Ruled out: waiting for a *fast* status instead (dropping `GitPush.state` from the critical path) — better, but still a process round-trip between click and feedback, and push state is not what the row needs anyway. Ruled out: animating a provisional state (spinner per row) — the answer is known at exit 0; showing it is cheaper than decorating the wait.

### A busy refresh is kept, not dropped

`refresh()`'s `guard !isBusy … return` becomes the navigator's own shape: note that another refresh is wanted, run it when the current pass ends. The navigator has `wantsAnotherGitStatus` for exactly this reason; the changes pane not having it is how a click during a stage vanished.

### The diff render yields to a second click

The selection-changed diff render is deferred by the double-click interval and cancelled by a following activation or reselection, so the first click of a double-click never starts the parse the second click makes pointless. A single click pays the same total cost as today, ~a quarter-second later — a diff nobody has begun reading yet. Ruled out: skipping the render when `clickCount == 2` — at the first click the count is still 1, so the decision cannot be made there; the deferral makes it without predicting.

### The refresh sheds its double work

`EstateChanges.read(after:)` answers `.everything` for any repository that is not a superproject because its guard falls through; it learns to answer the cheap partial for a plain repository. The untracked-directory listings gathered by the first rebuild are handed to the second (the post-numstat one) instead of being re-shelled. Both are contained changes to code the trace named; neither changes what is shown.

### The path is instrumented before it is believed

`StallWatch.mark("stage")` around the operation and `mark("changes reload")` around the rebuild, first — so the before/after of every other decision here is two log lines rather than a feeling, and the next regression in this path names itself instead of logging as `idle`.

## Risks / Trade-offs

- [Optimistic move shows a state git then refuses] → the immediate status read corrects it; the window is the length of one porcelain status (~50 ms here). The status was always the authority.
- [Reusing the actor keeps a stale status cache across an external `.git` write] → the watcher path still tells the actor to refresh its status; what it stops doing is *rebuilding* the actor. The fingerprint check itself is the existing, tested invalidation for the ignored walk.
- [Deferring the diff render delays single-click reading by the double-click interval] → a fixed, small lag on an action whose current cost is an unbounded-feeling stall elsewhere; if it reads as sluggish the interval can shrink — the mechanism stays.
- [Two rebuilds sharing untracked listings could show a directory staleness for one pass] → the two rebuilds are milliseconds apart over the same model; the next refresh re-reads regardless.

## Open Questions

- Whether `GitPush.state` belongs in the stage's refresh at all (it re-runs per stage and feeds the Push button, not the trees) — left in place here; moving it to the watcher-echo pass only is a follow-up the marks will justify or kill.
