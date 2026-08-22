# House rules

How not to break this machine while working on Abydos. **Every rule here was
learnt from an agent doing the wrong thing**, and every one had to be typed into
a prompt by hand — five times in one day, which is what item 0471 is about.

They are here because this file is read without being pointed at, which is how
every agent working here arrives at them. **There is one copy**, and nothing
repeats these rules.

This project used to keep a `backlog-spec` backlog in `.abydos/backlog`, and
`project.md` there named this file so that an agent the backlog started reached
the same copy. That backlog is gone — the work it held is proposed as OpenSpec
changes under `openspec/changes`, and the account it kept in
`.abydos/backlog/spec` is `openspec/specs`. It is in the git history, where a
hundred and thirty-eight completed items and what they decided can still be
read. The `backlog-spec` tool itself is unaffected: it is somebody else's
project and this was only one of its users.

What is true *today* — which container runtime is up, which session is somebody's
— is not here. That is `.abydos/today.md`, kept separate so this file can be
trusted: a document that mixes "never push" with "Docker is stopped this
afternoon" teaches an agent to distrust all of it.

A rule with **[guarded]** beside it is one a program keeps, so it is one to stop
worrying about. The rest are where the attention belongs.

## Never push, and never publish

Never `git push`. Never publish anything to a registry, a package index or a
container repository.

An agent once created five public Docker Hub repositories that nobody asked for.
Nothing here needs to reach anybody else's machine to be finished, and a commit
somebody can read is the deliverable.

**Deleting a merged branch from `origin` is the one exception**, and only when
somebody asks for it. What the rule guards against is something *arriving* where
others can see it — a repository, a package, a commit nobody reviewed. A branch
whose every commit is already in `origin/main` puts nothing there that is not
there twice over, and the delete is undone by pushing the ref back.

Prove it, per branch, and not from the listing alone:

    git merge-base --is-ancestor <branch> origin/main

`git branch -r --merged origin/main` gathers the candidates; the check above is
what makes each one true. Write the SHAs to a file before the delete, so a branch
can be put back by name and not by memory. Anything that check does not cover is
still under the rule.

Locally, `git branch -d` will refuse a branch that is merged to `main` while
sitting ahead of its own stale upstream ref — it says "not fully merged" and
means "your `origin/<branch>` is behind". That is the remote ref being old, not
work being lost. `--is-ancestor` against `main` is the question worth asking, and
`-D` follows from its answer.

## Collect the worktrees git cannot see

`git worktree prune` collects only what is *registered*, and a worktree whose
repository was renamed or moved is registered nowhere: the record lived in the
old `.git/worktrees`, and it went with it. `git worktree list` never mentions the
directory, no prune will ever reach it, and it simply sits there.

One sat under `.claude/worktrees` for two weeks — 4.9 GB of checkout and build
output, pointing at a `/Users/philipparndt/dev/ideai/.git` that stopped existing
when this repository became `abydos` — on a disk at 99% full.

So look at the directories, not at the registration:

    ls -d .claude/worktrees/*/
    git worktree list --porcelain

A directory the second does not name is orphaned. Its `.git` file names the
repository it still wants; if that path is gone, nothing will collect it but you.

Ask what is in it before you delete it — which git will not tell you, having
refused to open it. Lend it an index and ask against the tip it was left on:

    export GIT_DIR=$PWD/.git GIT_WORK_TREE=<dir> GIT_INDEX_FILE=<scratch>/probe.index
    git read-tree <tip>
    git diff --stat                              # changes against that tip
    git status --short --untracked-files=normal  # anything never committed

Silence from both, and a tip that `--is-ancestor` puts in `main`, means the
directory is build output wrapped around a commit you already have.

A *registered* worktree fails differently: it can be locked by a session that
died, and the lock names the pid that took it, long since gone. `prune` skips a
locked worktree and does not say so. `git worktree unlock <path>`, then prune.

## Never `make install`

`make install` replaces the app in `/Applications` — the one somebody is using
right now. Build and run `build/Abydos.app/Contents/MacOS/Abydos` directly.

Replacing a bundle a running copy is mapped from is also how the kernel comes to
kill it with `CODESIGNING / Invalid Page` minutes later, with no obvious
connection to the install that caused it. `Scripts/install.sh` swaps by rename to
survive that, and it is still not yours to run.

## Build with a throwaway bundle id and an unpinned UUID

    make build BUNDLE_ID=de.rnd7.abydos.itemNNNN PIN_UUID=0

A build under the real identifier with an unpinned UUID takes the macOS Local
Network grant away from the installed app, which cost a day to diagnose: the
symptom is somebody else's app losing a permission they never touched.

## Never a bare `tmux` command

Always `-L <name>` or `-S <path>`, **including kills**. `$TMUX` overrides
`TMUX_TMPDIR`, so a `TMUX_TMPDIR` of your own isolates nothing when you are
already inside a session.

A killed agent destroyed the shared server twice and stopped other agents dead.
The sessions named `abydos`, `platform`, `backlog-spec` and `check` are
somebody's.

## Guard every app launch

Before driving the app, assert it opened the project you asked for. `--open` is a
request, not a guarantee: a window can come up on a project from the recent list
instead, and everything you then do, you do to somebody else's files.

An agent renamed a file in a real `~/.config/zshutil` this way. Drive against a
copy under the scratchpad, never a real checkout.

## Pre-seed a throwaway defaults domain

`Settings.migrate` writes real settings. Give the run a domain of its own,
pre-seeded, and delete it afterwards.

## `TestDefaults.make()`, never `UserDefaults(suiteName:)` — [guarded]

Kept by `NamedSuiteTests`, after `UserDefaults(suiteName:)` littered the machine
with thousands of plists twice.

## `xcrun swift`, never plain `swift`

The plain one is whichever toolchain manager got to the `PATH` first, which is
not the one the build uses.

## Say what the load was, under any timing

Concurrent agents have made a performance test red twice in one day:
`drawingIsFastEnoughToDoWhileSomebodyTypes` at 0.605 s against a 0.5 s budget
under load 35, and `PseudoTerminalTests` waiting 124 s under load 65 for output
that takes 0.35 s.

A number without the load beside it cannot be told from a regression.
`MachineLoad.said` prints it; `Stopwatch.maySay` decides whether a bound may be
asserted at all, and `make timing` is the run that asks for one.

## Before you finish

`make test` and `make warnings`, both clean. `make warnings` is a separate verb
on purpose and is not part of `make build`: an incremental build only reports the
files it recompiled, so a warning is seen once by whoever happens to be watching
and then never again.

**Their exit codes mean what they say.** `make test` used to exit 0 over a suite
with failures in it — the run was backgrounded as a pipeline and the status
reported was `tee`'s — so anything that checked the code rather than reading the
output had been told the suite was green for as long as the script existed. It
was found by grepping a log. Trust the code now, and if a run leaves no status
behind at all, that counts as a failure.
