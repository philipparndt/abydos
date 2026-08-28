# Three hundred submodules are one working copy

## Why

A refactoring that crosses a microservice estate is done in a superproject that
holds two or three hundred repositories as submodules. **This program has never
heard of a submodule.** `grep -rin submodule Sources/AbydosKit/Git
Sources/AbydosApp/Git Sources/AbydosKit/Forge` returns nothing, and the design
that built the current git tool said so on purpose:

> Signing, submodules, LFS, bisect. They belong behind the typed command surface
> if anywhere, and that surface is not in this change.
> — `openspec/changes/archive/2026-08-24-the-git-tool-becomes-one-tree-and-two-pages/design.md:39`

What that non-goal costs is not a missing feature. It is three failures, and two
of them are already in the code:

**1. The status this program runs is the slow one, and it runs it on every
filesystem event.** `GitWorkingCopy.status(in:)` runs `git status
--porcelain=v1 -unormal --no-renames -z` in one root. In a superproject that
call recurses into every submodule, serially, inside the one process. Measured
on a synthetic superproject of 200 submodules of eight files each — ten cores,
load averages 9.2 to 21.2 across the run, `git version 2.54.0 (Apple Git-157)`:

| what was asked | seconds |
| --- | --- |
| what `GitWorkingCopy.status` runs today | **1.61** |
| the same call, `--ignore-submodules=all` | 0.09 |
| `git status --porcelain=v2` (states the submodule field too) | 1.54 |
| `git submodule status` — the obvious approach | **5.37** |
| one submodule asked on its own | 0.01 |
| all 200 asked at once, twelve concurrent | **0.45** |
| the inventory from `git ls-files --stage`, gitlinks only | **0.01** |

The superproject's own status is 0.09 s; the other 1.5 s is git walking two
hundred repositories one after another. That number lands on a code path whose
comment already explains that it "runs on every filesystem event, which during a
build is dozens a minute" — a 0.11 s call was worth a paragraph of justification
there, and in a superproject the same call is fifteen times that. At 300
submodules it extrapolates to about 2.4 s per event.

**2. A submodule is deliberately not somewhere you can work.**
`ProjectRoot.isSubmodulePointer` reads a `.git` file, sees `modules/` in it, and
keeps climbing — so a terminal that steps into `svc-47` does not move the window,
which is right, and `GitRepository.discover(from:)` then answers the
*superproject* for every file inside it, which is not. Every verb built on that
answer — stage, unstage, discard, commit, diff, blame, push — is aimed at the
wrong repository for any file under a submodule. `Project` holds one
`GitRepository`, and a superproject is not one repository.

**3. There is nowhere to see the estate.** The refs tree shows one repository's
branches. The commit page composes one repository's commit. `GitHubPullRequests`
lists one repository's pull requests. A refactoring that touches forty services
is forty branches, forty pull requests and forty review states, and the only
place that has ever held them together is a spreadsheet somebody keeps by hand.

There is no originating `.abydos/backlog` item; the backlog was retired before
this was raised.

## What Changes

**A superproject is read once, in parallel, and then never swept again.** The
inventory — which submodules exist, at which commit the superproject records
them, where they are on disk — comes from `git ls-files --stage` filtered to
mode `160000`, which is 0.01 s for 200 and needs no process per submodule. The
overview draws from that immediately. State fills in behind it from a bounded
fan-out of one `git status` per submodule, 0.45 s for 200 against the 1.61 s the
one recursive call costs today, and the recursive form is never run again.

**After the first sweep, work is per submodule and event-driven.** Every
submodule's git directory lives under the superproject's own
`.git/modules/<name>` — verified: 200 of 200 — so one watcher over `.git` sees
every submodule's refs and index, and one watcher over the work tree sees every
submodule's files. Three hundred submodules need two watchers, not six hundred.
A change under `svc-47/` re-reads `svc-47` alone, which is 0.01 s.

**An overview of the estate.** One page that is the answer to "where is this
refactoring": a row per submodule, what changed in it, which branch it is on,
whether it is ahead of its remote, whether its recorded commit has moved, and
whether it has a pull request and what state that pull request is in. Sorted so
the rows that need something come first, filterable, and readable at three
hundred rows — which means the row is cheap and the page is virtualised.

**Changes across submodules are one list.** The commit page's two trees gain the
repository a change belongs to, so the estate's unstaged work is one thing to
read and one thing to stage, and staging a path runs `git add` in the repository
that owns it rather than in the superproject that does not.

**Conflicts include the kind only a superproject has.** A gitlink conflict is
two commits, not two texts, and no merge tool opens it. It is named as what it
is — which commit each side recorded, what is between them — and resolved by
choosing a side or by pointing it at a third commit.

**A commit across repositories is one act.** Committing the estate commits each
dirty submodule with the same message, then stages the gitlinks those commits
moved and commits the superproject. It is not atomic and will not claim to be:
what it does is say, per repository, what happened, and leave a partial run
resumable rather than half-explained.

**Pull requests are raised and tracked as a set.** One title and body, a branch
name per repository, a pull request per changed submodule plus the superproject,
raised through the `gh` this repository already uses. The set is then a thing
with a state: how many are open, assigned, reviewed, merged, red. This is the
half a spreadsheet is doing today.

**BREAKING** — nothing in the public API is removed, but `Project.git` stops
being the whole answer for a superproject. Callers that assume one repository
per project are corrected to ask which repository owns a path.

## Capabilities

### New Capabilities

- `submodules`: what a submodule is to this program — the inventory, the state
  of each, which repository owns a path, what it costs to know all of that, and
  how it stays true without sweeping. Holds the overview page.
- `cross-repository-commits`: staging, discarding, gitlink conflict resolution
  and committing across the superproject and its submodules as one act, with a
  partial run reported per repository.
- `cross-repository-pull-requests`: a set of pull requests raised from one
  description across many repositories, and tracked to merge as one object.

### Modified Capabilities

- `version-control`: the two file trees span repositories, so a change carries
  which repository it is in and a path is staged in the repository that owns it,
  not in the one the tree is rooted at.
- `git-refs-tree`: the tree gains the submodules under the working copy, and the
  repository row says it is a superproject and how many it holds.
- `git-safety`: the safety net covers an operation that touches many
  repositories — what is backed up, and what a partial failure leaves behind.
- `git-changes-detail`: a gitlink is a changed row of a kind the tree has not
  had, and it says how far the recorded commit moved rather than how many lines
  changed.

## Impact

**Code.** `Sources/AbydosKit/Git`: `GitWorkingCopy` (status per repository rather
than per project), `GitRepository` (ownership of a path; the recursive status
retired), `RepositoryWatcher` (one watcher, many repositories),
`GitChangeTree`/`PathTree` (a repository above the folders), `GitConflicts` (the
gitlink kind). `Sources/AbydosKit/Project`: `Project` holds an estate rather than
a repository; `ProjectRoot` keeps its climbing rule, which stays correct.
`Sources/AbydosKit/Forge`: `GitHubPullRequests` and `GitForge` asked per
repository, and a set above them. `Sources/AbydosApp/Git`: the panes and the
commit page, plus the new overview page.

**Ordering.** The pull request half sits on `pull-requests`, which is the
in-flight `review-a-pull-request` change and not yet in `openspec/specs`. The
submodule and commit halves do not, and are worth landing first on their own.

**Dependencies.** None added. `git` and `gh` are processes this program already
runs.

**Cost.** Concurrency is the new resource. A bounded pool of git processes is
the whole performance argument, and an unbounded one is three hundred processes
against ten cores — measured at no better than twelve concurrent, and a way to
make the machine unusable during a build.

**Risk.** The measurements above are from a synthetic superproject of small
repositories. Two hundred real microservices are larger and their statuses are
slower; the shape of the argument holds and the constants do not. A real estate
has to be measured before the numbers here are quoted as budgets.
