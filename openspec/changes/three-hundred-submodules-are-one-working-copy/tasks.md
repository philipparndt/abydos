> **Where this stands.** Every group is built, tested, and driven against a real
> estate under the scratchpad. `make test` is 3771 passing and `make warnings`
> clean.
>
> **Everything below is done**, except the one line noted against 11.6: a
> submodule's pull request opens for reading, and the verbs that would check out
> or finish a review are not offered there because they are wired to the
> project's root and would act on the wrong repository.
>
> Three of the open questions the design raised have been answered by building
> the thing. The overview is a page *and* the refs tree has a section, and they
> do not duplicate: the section shows what needs something and counts the rest,
> the page shows all of it. The concurrency ceiling stayed beside
> `GitRepository.run` rather than inside it, and the forge got a ceiling of its
> own because its limit is the forge's rather than this machine's. Whether the
> superproject's gitlink commit is automatic is still the caller's to say, which
> is where it was left deliberately.
>
> Still open, and unstarted: nested submodules deeper than one level, and
> submodules inside a linked worktree. Both are named as non-goals in
> `design.md`.
>
> **On the suite's reliability here.** Under load above about four runnable
> threads a core — which this machine sat at while this was being written, from
> its own builds — a different unrelated live test fails each run on a wait or a
> deadline: `DebugRefusalLiveTests`, `LSPTests`, `LocalNetworkProbeTests`,
> `ToolProcessTests`. All four pass in isolation, none of them touches this
> change, and the suite is green at load below that. This is the shape 0435 and
> 0472 are about, and it is recorded here rather than hidden behind a re-run.

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
- [x] 5.3 The refs tree's submodules section lists only what has something to
      report and counts the clean ones. A submodule row expands to its changed
      files, never to its branches
- [x] 5.4 The repository row says it is a superproject and how many it holds; its
      distance stays the superproject's own, not a sum
- [x] 5.5 Folded state and selection survive a rebuild across repositories, the
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
- [x] 8.5 Push is the same shape, reported the same way

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
- [x] 9.5 A way in from the refs tree's submodules section and from the
      repository row — *the section header carries the verb; the repository
      row says how many submodules it holds and keeps its own, because a
      second verb there would dilute the remote traffic it is pinned for.
      The spec delta was corrected to say that rather than the reverse*

## 10. The safety net across repositories

- [x] 10.1 One question for the whole operation, naming how many repositories it
      covers
- [x] 10.2 Every backup made before any repository is touched
- [x] 10.3 A partial run names what changed, what did not, and every backup ref
- [x] 10.4 A remembered choice stays with the repository it was given for

## 11. Pull requests as a set — after `review-a-pull-request` has landed

- [x] 11.1 Raise a set: one branch, one title, one body, a pull request per
      repository with commits on that branch, the superproject included
- [x] 11.2 Skipped and already-open are outcomes, not failures
- [x] 11.3 A bounded `gh` fan-out sized for network rather than disk; a rate
      limit reported as itself and never as an empty set
- [x] 11.4 State read from the forge every time and never stored. No local record
      of numbers; `gh search prs` not used
- [x] 11.5 The set's sentence: how many open, awaiting review, approved, merged,
      red — with red first
- [x] 11.6 A row opens that pull request as the page `pull-requests` defines —
      *reading only: checking out and finishing a review are wired to the
      project's root and would act on the wrong repository, so they are not
      offered on a submodule's pull request*

## 12. Finishing

- [x] 12.1 Driven verification against a generated estate under the scratchpad,
      never a real checkout, with a throwaway defaults domain deleted afterwards
- [x] 12.2 `make build BUNDLE_ID=de.rnd7.abydos.submodules PIN_UUID=0` — never
      `make install`
- [x] 12.3 `make test` and `make warnings`, both clean, and their exit codes
      trusted
- [x] 12.4 `Scripts/file-size-allowed.txt` updated for whatever grew
- [x] 12.5 No `.abydos/backlog/spec/*.md` file is made untrue by this change:
      that backlog was retired and its account now lives in `openspec/specs`.
      The files this change makes untrue are `openspec/specs/version-control`,
      `git-refs-tree`, `git-safety` and `git-changes-detail`, and each has a
      delta in this change saying how
