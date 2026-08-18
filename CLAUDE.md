# House rules

How not to break this machine while working on Abydos. **Every rule here was
learnt from an agent doing the wrong thing**, and every one had to be typed into
a prompt by hand — five times in one day, which is what item 0471 is about.

They are here because this file is read without being pointed at, which covers
the agents nobody started through the backlog, and that is most of them. It is
also the file `.abydos/backlog/project.md` names, so an agent the backlog started
reaches the same copy. **There is one copy.** Nothing repeats these rules — not
the prompt `abydos-backlog start` builds, which argues against repeating them in
its own comment and is right, and not `project.md`, which belongs to the
published `backlog-spec` tool rather than to this project.

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
