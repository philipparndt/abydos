> **Where this stands.** Groups 1–6 and 8–10 are built, tested and driven
> against a real estate: the inventory, ownership, the two-question status, the
> bounded fan-out, event attribution, estate-wide staging and the commit run,
> gitlink movement, the changes tree with its repository rows, and the overview
> page with its ordering, filter and summary. `make test` (3728) and
> `make warnings` are clean.
>
> Group 7 is done too: a gitlink conflict is read from `ls-files -u`, described
> in commits, and resolved three ways — take either side, or merge inside the
> submodule and take what that leaves, which is what git's own hint tells you to
> do.
>
> What is left: the refs tree's own submodules section (5.3, 5.4), pushing the
> estate (8.5), the safety net's partial-run report and per-repository
> remembered choice (10.3, 10.4), and the pull request set (group 11), which
> waits on `review-a-pull-request`. The overview is reached from
> View ▸ Submodules (⇧⌘M) meanwhile, so nothing is unreachable. Unticked boxes
> below are unstarted, not half-done.
>
> **The refs tree section is worth deciding before it is built.** The design's
> own open question asked whether the overview should be a page or the refs tree
> grown up; now that the page exists and works, a second listing of the same
> submodules in a 300 pt column may be duplication rather than the tree keeping
> its promise to hold everything. That is a judgement about this program, not a
> gap in the work.

## 1. The estate: what a superproject is, before anything is drawn from it

- [x] 1.1 `Sources/AbydosKit/Git/GitSubmodules.swift`: the inventory from `git
      ls-files --stage -z` filtered to mode `160000` — path, recorded commit —
      plus name and URL from `.gitmodules`. One call each, no process per
      submodule. The index decides; `.gitmodules` decorates
- [x] 1.2 A submodule the index names and disk lacks is `absent`; a repository on
      disk the index does not name is `untracked`. Neither is fetched or hidden
- [x] 1.3 `GitEstate`: the superproject plus its submodules, holding the
      inventory sorted by path
- [x] 1.4 `GitEstate.owner(of:)` — the longest submodule path prefixing a path,
      by binary search. No process, no actor hop, answers for paths that do not
      exist yet. Property test: every path under a submodule resolves to it, and
      a sibling directory whose name is a prefix of a submodule's does not
- [x] 1.5 Tests over recorded `ls-files --stage` and `.gitmodules` output for an
      estate, an estate with an absent submodule, and a repository with none

## 2. Reading the estate without the recursive status

- [x] 2.1 The superproject's call gains `--ignore-submodules=dirty`. Test that it
      reports a moved gitlink and stays silent about a merely dirty work tree —
      the split the whole design rests on
- [x] 2.2 A bounded fan-out of `GitWorkingCopy.status(in:)`, one per submodule,
      capped at `min(activeProcessorCount, 12)` and cancellable. Closing the
      project stops one in flight
- [x] 2.3 The recursive form is never run: assert it, by asserting the flag is on
      every superproject status this program issues
- [x] 2.4 `GitWorkingCopyStatus` per repository, and an estate-wide view over
      them that does not flatten away which repository a change is in
- [x] 2.5 Timing, on a generated estate: `MachineLoad.said` beside every number,
      `Stopwatch.maySay` deciding whether a bound may be asserted at all. The
      claim under test is the ratio — fan-out against the recursion — not a
      constant
- [x] 2.6 A generator for a synthetic estate in the test support code, so this is
      reproducible rather than a number somebody once saw

## 3. Staying true without sweeping

- [x] 3.1 One `RepositoryWatcher` over the superproject's `.git` covers every
      submodule, because each submodule's git directory is
      `.git/modules/<name>`. Assert that layout rather than assume it
- [x] 3.2 A filesystem event names directories; resolve each to its owner and
      re-read only those repositories
- [x] 3.3 The full sweep runs on open and when `.git/index` or `.gitmodules`
      moves, and at no other time
- [x] 3.4 Test: a write under one submodule re-reads that one and no other; a new
      gitlink in the index re-reads the inventory; loose objects re-read nothing

## 4. Every verb aimed at the repository that owns its path

- [x] 4.1 Stage, unstage and discard group their paths by owner and run one
      command per repository, each with paths relative to that repository
- [x] 4.2 Diff, blame, log and the code links ask the estate which root a path
      belongs to
- [x] 4.3 `ProjectRoot`'s climbing rule is unchanged, and a test says why: a
      terminal entering a submodule does not move the window, while a file inside
      it still stages in the submodule
- [x] 4.4 `Project` holds an estate; `Project.git` keeps meaning the
      superproject, and call sites move deliberately rather than by a rename that
      makes them all compile

## 5. The trees gain a repository, and only where there is one

- [x] 5.1 `GitChangeTree`/`PathTree` take a repository above the folders. A
      project with no submodules gains no row: a level with one child that is
      always the same child says nothing
- [x] 5.2 The same path changed in two submodules is two rows, not one
- [ ] 5.3 The refs tree's submodules section lists only what has something to
      report and counts the clean ones. A submodule row expands to its changed
      files, never to its branches
- [ ] 5.4 The repository row says it is a superproject and how many it holds; its
      distance stays the superproject's own, not a sum
- [ ] 5.5 Folded state and selection survive a rebuild across repositories, the
      way they already do across folders

## 6. A gitlink is a changed row of its own kind

- [x] 6.1 A gitlink row reads `12 ahead`, `3 behind` or diverged, from one
      `rev-list --count --left-right`, and names the subject it now points at
- [x] 6.2 No line count on a gitlink, and none counted into its parent folder
- [x] 6.3 Moved and dirty are two facts on one row, in that order
- [x] 6.4 Counts are asked only of repositories known to have changed — six
      commands for six changed submodules out of two hundred

## 7. Conflicts a merge tool cannot open

- [x] 7.1 `GitConflicts` gains the gitlink kind: both sides' commits, their
      subjects, and what lies between them
- [x] 7.2 Three ways out — take either side, or a third commit from the
      submodule's history — each a `git add` of the gitlink
- [x] 7.3 A text conflict inside a submodule stays a text conflict in that
      repository and is not confused with a conflict about the gitlink

## 8. Committing the estate

- [x] 8.1 Commit each dirty submodule with the shared message, then stage the
      moved gitlinks and commit the superproject
- [x] 8.2 An outcome per repository — committed and at which commit, failed and
      with what git said, skipped and why. Every repository has one
- [x] 8.3 Resumable: running it again acts on what is still dirty
- [x] 8.4 No rollback, and a test that says so: a failure at the fourth of six
      leaves five commits standing
- [ ] 8.5 Push is the same shape, reported the same way

## 9. The overview

- [x] 9.1 A page: a row per submodule with changes, branch, distance, gitlink
      movement, and room for a pull request state
- [x] 9.2 Drawn from the inventory before any status lands. A row without a
      status says so and never says clean
- [x] 9.3 Ordered by what needs something — conflicted, changed, ahead, clean —
      and filterable, saying how many rows a filter hid
- [x] 9.4 The row's model is computed when its status lands, not while drawing,
      and the view is virtualised: three hundred rows cost what thirty do.
      Measured, with the load said
- [ ] 9.5 A way in from the refs tree's submodules section and from the
      repository row

## 10. The safety net across repositories

- [x] 10.1 One question for the whole operation, naming how many repositories it
      covers
- [x] 10.2 Every backup made before any repository is touched
- [ ] 10.3 A partial run names what changed, what did not, and every backup ref
- [ ] 10.4 A remembered choice stays with the repository it was given for

## 11. Pull requests as a set — after `review-a-pull-request` has landed

- [ ] 11.1 Raise a set: one branch, one title, one body, a pull request per
      repository with commits on that branch, the superproject included
- [ ] 11.2 Skipped and already-open are outcomes, not failures
- [ ] 11.3 A bounded `gh` fan-out sized for network rather than disk; a rate
      limit reported as itself and never as an empty set
- [ ] 11.4 State read from the forge every time and never stored. No local record
      of numbers; `gh search prs` not used
- [ ] 11.5 The set's sentence: how many open, awaiting review, approved, merged,
      red — with red first
- [ ] 11.6 A row opens that pull request as the page `pull-requests` defines

## 12. Finishing

- [ ] 12.1 Driven verification against a generated estate under the scratchpad,
      never a real checkout, with a throwaway defaults domain deleted afterwards
- [ ] 12.2 `make build BUNDLE_ID=de.rnd7.abydos.submodules PIN_UUID=0` — never
      `make install`
- [ ] 12.3 `make test` and `make warnings`, both clean, and their exit codes
      trusted
- [ ] 12.4 `Scripts/file-size-allowed.txt` updated for whatever grew
- [x] 12.5 No `.abydos/backlog/spec/*.md` file is made untrue by this change:
      that backlog was retired and its account now lives in `openspec/specs`.
      The files this change makes untrue are `openspec/specs/version-control`,
      `git-refs-tree`, `git-safety` and `git-changes-detail`, and each has a
      delta in this change saying how
