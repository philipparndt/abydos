## Why

Staging a file or folder from the changes tree takes one to five seconds to
show — long enough that whether the double-click registered at all is in
doubt, which was the report on 2026-08-31, with a screenshot of fourteen
changed files. The delay is not git's: `git add` and the porcelain status
each cost tens of milliseconds in this very repository. It is the app's own
sequence, traced and measured:

- the `.git` watcher path calls `Project.loadGit()`, which *discovers a new
  `GitRepository`* — throwing away the ignore-rules fingerprint, so the walk
  the code itself calls "the expensive one" (`git status --ignored`, 0.82 s
  warm and 1.56 s cold over a 2.9 GB `build/`) reruns after **every stage**,
  though its own comment promises it is paid only when a `.gitignore` is
  saved;
- the row cannot move before a full status re-read and two from-scratch tree
  rebuilds — there is no optimistic update anywhere;
- the first click of the double-click renders a diff inline on the main
  thread (194 ms in the stall log), and the stage is queued behind it;
- the app's own index write echoes back through FSEvents ~0.4 s later and
  the whole refresh runs a second time;
- a refresh that arrives while a stage is in flight is silently dropped
  (`guard !isBusy`), with no retry — the "did my click even register" case.

There is no originating `.abydos/backlog` item: this comes from that direct
report.

## What Changes

- Staging and unstaging move the affected rows at once: on the command's
  exit 0 the rows switch sides immediately, and the status re-read that
  follows confirms or corrects.
- The repository watcher stops rediscovering the `GitRepository` on every
  `.git` event; the existing actor — its status cache and its ignore-rules
  fingerprint with it — is reused, so the ignored-files walk runs only when
  ignore rules actually changed, as its comment already promises.
- A refresh arriving while the pane is busy is kept and run after, the way
  the project navigator already coalesces (`wantsAnotherGitStatus`), instead
  of being dropped.
- The diff render no longer stands in front of the stage: rendering is
  deferred briefly and cancelled by a rapid reselection or activation, so a
  double-click stages without first paying for a diff nobody asked to read.
- The cheap partial-refresh path applies to repositories without submodules
  instead of always answering `.everything`, and one rebuild's untracked-
  directory listings are reused by the second instead of shelling out again.
- `StallWatch` marks around the stage and the changes reload, so the next
  report of this kind names itself in the log instead of counting as "idle".

## Capabilities

### Modified Capabilities

- `version-control`: gains requirements for staging's responsiveness — the
  row moves at once, a busy refresh is coalesced rather than dropped, and
  the app's own writes do not re-trigger the expensive ignore walk.
  Additions only: no existing requirement speaks to any of this.

### New Capabilities

<!-- none -->

## Impact

- **AbydosApp**: `MainWindowController`'s watcher closure (reuse, not
  rediscover), `ChangesPane` (optimistic move, coalescing, reload cost,
  StallWatch marks), `SidebarController.showDiff` timing.
- **AbydosKit**: `Project.loadGit` (refresh in place), `EstateChanges.read`
  (the partial path for plain repositories).
- **Tests**: the optimistic move and coalescing are pane behaviour driven
  through the existing changes-tree driver; the kit changes get unit tests
  beside `EstateChangesTests`/project tests.
- **Risk**: an optimistic row confirmed by the real status can flicker back
  on a failed partial stage; the status was always the authority and stays
  it.
