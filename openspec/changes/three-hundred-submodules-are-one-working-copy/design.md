# Design

## Context

`Project` holds one `GitRepository`. `GitWorkingCopy.status(in:)` runs one `git
status` in one root. `RepositoryWatcher` watches one `.git`. Every git verb in
`AbydosKit/Git` takes a `root: URL` and means "the repository", because until now
a project has had one.

A superproject of 200–300 microservices breaks that in three places at once — the
cost of the status, the ownership of a path, and the absence of anywhere to see
the estate. The proposal has the measurements; this says what to build from them.

All numbers below are from the same synthetic superproject: 200 submodules of
eight small files each, ten cores, load averages between 4.9 and 21.2 over the
session, `git version 2.54.0 (Apple Git-157)`. They are constants from a small
estate and are quoted here as ratios, not budgets.

## Goals / Non-Goals

**Goals:**

- Reading the state of 300 submodules costs less than reading 200 costs today.
- After the first sweep, nothing is swept. A change in one submodule re-reads
  that submodule.
- One page answers "where is this refactoring", at 300 rows, without stutter.
- A path is staged, discarded, diffed and blamed in the repository that owns it.
- A gitlink conflict is a first-class conflict with its own way out.
- A pull request set is one object with one state.

**Non-Goals:**

- **Atomicity across repositories.** Nothing this program can do makes 200
  commits and 200 pushes one transaction, and pretending otherwise is the worse
  failure: a rollback that rewrites history in repositories somebody else has
  already fetched. A partial run is reported per repository and resumed.
- **A merge tool.** The archived design's non-goal stands. What is added is the
  one conflict kind no external merge tool can open — a gitlink — and that is
  resolved by choosing a commit, not by editing text.
- **`git submodule` as a user-facing verb.** No `init`, `deinit`, `sync`,
  `--recurse-submodules` checkbox. The program knows what the index says and what
  is on disk; the estate is read, not administered.
- **Nested submodules deeper than one level** in this change. The inventory
  records the depth it finds; only the first level is acted on. See Open
  Questions.
- **Forges other than GitHub.** `gh` is the only forge client here.
- **Cloning an estate.** The superproject is already checked out and its
  submodules already populated. A submodule the index names and disk does not
  have is shown as absent, not fetched.

## Decisions

### The recursive status is retired, and replaced by two questions

`GitWorkingCopy.status(in:)` on a superproject runs `git status` with default
submodule handling, which walks every submodule serially inside the one process:
1.61 s for 200. The superproject's own status is 0.09 s of that.

So ask two questions instead of one:

1. **The superproject, `--ignore-submodules=dirty`** — 0.09 s. This is not a
   weaker answer. It reports the superproject's own files *and* every gitlink
   whose recorded commit has moved, which is precisely what only the superproject
   knows. Verified: with four submodules dirty in their work trees and one
   submodule's HEAD moved, this call printed `M svc-77` and nothing else.
2. **Each submodule, on its own, fanned out** — 0.01 s each, 0.45 s for 200 at
   twelve concurrent. This is the working-tree detail, and it is the answer that
   parallelises.

**Ruled out — `git submodule status` / `submodule foreach`.** 5.37 s for 200,
3.3× worse than the recursion it would replace, because it is a shell and a
process per submodule, serially. `--cached` does not help: 5.82 s.

**Ruled out — `git status --porcelain=v2` and its submodule field.** v2 states
each gitlink's submodule flags (`S.M.` for "has modified tracked content") in the
same output, which reads like one cheap call that says which submodules are
dirty. It is not cheap: 1.54 s, because the flags come *from* the same serial
recursion. It buys 0.07 s over the call it replaces and forfeits the fan-out.

**Ruled out — a status cache keyed on mtime.** The index and the work tree are
already the cache; a second one is a second thing to invalidate, and the
event-driven refresh below makes the sweep rare enough that it does not pay.

### The inventory comes from the index, not from a process per submodule

`git ls-files --stage` filtered to mode `160000` names every submodule and the
commit the superproject records for it: **0.01 s for 200**. `git config --file
.gitmodules --list` adds the configured URL and name: another 0.01 s.

The overview draws from those two calls before any status has run. The rows exist
in ten milliseconds; what fills in behind them is state. A page that appears
whole and then annotates itself is the difference between "instant" and "half a
second", and half a second on opening a project is what this feature would
otherwise be remembered for.

**Ruled out — reading `.gitmodules` alone.** It is the configuration, not the
truth. A submodule removed from the index but left in `.gitmodules`, or added to
the index by someone whose `.gitmodules` you have not pulled, are both real and
both common mid-refactoring. The index decides; `.gitmodules` decorates.

### Two watchers, not six hundred

Every submodule's git directory is under the superproject's own
`.git/modules/<name>` — verified, 200 of 200, with each submodule's `.git` file
reading `gitdir: ../.git/modules/svc-N`. So:

- One `RepositoryWatcher` over the superproject's `.git` sees every submodule's
  refs, HEAD and index. Its existing `matters(directory:)` rule — skip
  `/objects`, skip `/lfs` — applies unchanged and now skips 300 object stores.
- One `FileSystemWatcher` over the work tree sees every submodule's files,
  because a submodule's work tree is a directory inside the superproject's.

An event names directories. The directory is resolved to its owning repository by
the same longest-prefix lookup described below, and **only that repository is
re-read**: 0.01 s. The full fan-out runs when the project opens and when the
inventory itself changes, which is when `.git/index` or `.gitmodules` moves.

**Ruled out — one `RepositoryWatcher` per submodule.** 300 FSEvents streams for
information that arrives on two, plus 300 debounce timers, plus a lifecycle to
get wrong when a submodule is added or removed. The layout makes it unnecessary.

**Ruled out — `--ignore-submodules=all` plus polling.** Polling 300 repositories
is the sweep this design exists to avoid, done repeatedly.

### A path is owned by the longest submodule prefix, resolved without a process

The estate holds its submodule paths in one array, sorted, work-tree-relative.
Ownership of a path is the longest of them that prefixes it, found by binary
search: no process, no actor hop, safe to call per row of a table.

This is the fix for failure 2 in the proposal. `GitRepository.discover(from:)`
answers the superproject for every file under a submodule, so every verb built on
it aims at the wrong repository. The verbs keep their `root: URL` parameter —
they are correct, they were just being handed the wrong root — and the call sites
ask the estate which root a path belongs to first.

`ProjectRoot`'s climbing rule is **not** changed. "You step into a submodule to
change something about the project you were already in" is right, and it is why
the window must not follow a terminal into `svc-47`. That is a different question
from which repository stages a file, and conflating them is what produced the
`warning: could not open directory 'sub/sub/'` failure `Project.gitRoot` already
documents.

**Ruled out — a dictionary from path to repository.** It answers only for paths
already seen; a new file under a submodule is the common case and would miss.
Prefix matching answers for paths that do not exist yet.

### Concurrency is bounded, and the bound is measured

Twelve concurrent git processes gave 0.45 s for 200 submodules; twenty-four gave
0.46 s. The plateau is at roughly the core count, and past it the processes
contend for the same disk and the same page cache. Unbounded is 300 processes
against ten cores while a build is running, which is how this feature would make
the machine worse at the job it was opened for.

So: one pool, `min(ProcessInfo.activeProcessorCount, 12)` for git, sized
separately for `gh` because that is network-bound and its plateau is elsewhere.
Cancellation matters as much as the bound — a sweep in flight when the project
closes must stop, not finish.

**Open where the bound belongs.** `GitRepository.run` currently hops each call to
a global queue with no ceiling, so a pool here is a pool beside it, not the
process plumbing's own. Whether the ceiling should move into `run` — where it
would also bound the rest of the app's git — is not decided in this change.

### The overview is a table, and its row is cheap

Three hundred rows, each with a name, a change count, a branch, an ahead/behind
pair, and a pull request state. The house rule about anything per row of a table
applies literally: the row's model is a value type computed when its repository's
status lands, not on draw, and the view is virtualised so that 300 rows cost what
30 do.

Sorting puts what needs something first — conflicted, then changed, then ahead of
its remote, then clean — because the page is opened to find the work, and three
hundred alphabetical rows of which four matter is a page nobody reads twice.

### A commit across repositories is a sequence that reports itself

Per dirty submodule: commit with the shared message. Then in the superproject:
stage the gitlinks those commits moved, and commit. Pushing is the same shape one
step later.

It is not atomic, and the design's job is to make the non-atomicity legible
rather than to hide it. Each repository's outcome is recorded — committed, failed
and why, skipped and why — and the run is resumable: repeating it acts on what is
still dirty and leaves what succeeded alone.

**Ruled out — two-phase commit with rollback.** The rollback is `git reset
--hard` in repositories that may already have been pushed, which is the exact
class of operation `git-safety` exists to refuse. A failure at repository 140 of
200 leaves 139 commits that are correct; destroying them to preserve a symmetry
nobody asked for is worse than saying which 139 they are.

**Open — whether the superproject commit is automatic.** Committing submodules
without bumping the gitlinks leaves the superproject dirty and the estate
half-recorded; bumping them automatically commits something the user did not
review. Both readings are defensible and this is not resolved.

### The pull request set is keyed by branch, and its state is never stored

A set is: one branch name, one title, one body, and the repositories it was
raised in. The branch name is the key. State — open, assigned, reviewed, merged,
red — is asked of `gh` per repository and never written down.

**Ruled out — a local record of pull request numbers.** It goes stale the moment
somebody merges from the web, it knows nothing on a second machine, and it is a
file to reconcile after every refactoring. The forge is the record; this program
reads it. The cost is N `gh` calls to refresh a set, which is why the `gh` pool
is sized for network and why refresh is asked for rather than polled — the
existing pull request work already made that choice for one repository.

**Ruled out — GitHub's own cross-repository search.** `gh search prs` would
answer a set in one call, but it is GitHub.com-shaped, its indexing lags by
minutes, and Enterprise hosts differ. Per repository is slower and true.

## Risks / Trade-offs

- **The measurements are from small repositories.** 200 microservices with real
  histories and real working trees will not be 0.01 s each. → The ratios hold
  because the parallelism is the argument, not the constant. Before any number
  here becomes a budget, `Stopwatch.maySay` and `MachineLoad.said` measure a real
  estate, per the timing rule.
- **A bounded pool starves under a build.** Twelve git processes competing with a
  compile is a sweep that takes seconds. → The sweep is rare by design, and it is
  cancellable; the common path is one 0.01 s status per event.
- **`Project.git` becomes a partial answer.** Every existing caller that assumed
  one repository per project is now subtly wrong for superprojects, and the
  compiler will not say so. → The estate is introduced with `Project.git` kept
  meaning the superproject, and call sites are moved deliberately rather than by
  a rename that makes them all compile.
- **A partial commit run is a state somebody has to understand.** → It is
  reported per repository and resumable, and no operation in the run is
  destructive on its own.
- **300 `gh` calls is a rate limit.** → Bounded, refresh on request, and a
  throttled reply is reported as itself rather than as an empty set — the
  distinction the pull request work already insists on.
- **Submodules and worktrees together.** The pull request review flow checks a
  branch out as a worktree; a worktree of a superproject has its own submodule
  state. → Out of scope here and named in Open Questions rather than guessed at.

## Migration Plan

There is no data to migrate. The change lands in the order the proposal's Impact
section gives, and each step is useful alone:

1. The estate, the inventory, the ownership lookup and the two-question status —
   with no user-visible change beyond a superproject no longer costing 1.6 s per
   filesystem event.
2. The refs tree and the changed-file trees gaining the repository dimension.
3. The overview page.
4. Cross-repository staging, gitlink conflicts, and the commit run.
5. The pull request set, after `review-a-pull-request` has landed.

A repository with no submodules takes the same path: the inventory is empty, the
estate is one repository, and the superproject call's `--ignore-submodules=dirty`
is a flag with nothing to ignore. There is no separate code path to keep true,
which is the point of not branching on "is this a superproject".

## Open Questions

- **Nested submodules.** A submodule containing submodules is real in some
  estates. The inventory can record depth cheaply; acting at depth multiplies
  every decision here. Deferred, not dismissed.
- **Where the concurrency bound lives** — beside `GitRepository.run` or inside
  it. See the decision above.
- **Whether the superproject's gitlink commit is automatic** after a
  cross-repository commit. See the decision above.
- **Submodules inside a linked worktree**, which the pull request review flow
  creates.
- **What "one message" means when the change differs per repository.** A shared
  message is right for a mechanical refactoring and wrong for a change that means
  something different in each service. Whether a per-repository override is worth
  its complexity is unknown until this is used.
- **Whether the overview is a page or the refs tree grown up.** Two hundred rows
  argues for a page; "the working copy is already in the tree" argues for the
  tree. The proposal says page; this is the decision most likely to be revisited
  after it is seen.
