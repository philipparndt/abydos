# 464. The installed backlog tool cannot find its own resources

`abydos-backlog start <n>` from the installed app dies with

    AbydosKit/resource_bundle_accessor.swift:44: Fatal error: unable to find
    bundle named Abydos_AbydosKit

**after it has already made the worktree, made the branch and moved the item to
`in-progress/`.** So the item looks started, the worktree is real and usable, and
the one thing `start` exists to do — hand it to an agent — is the thing that did
not happen. Nothing says so; the exit is a crash. Both 0451 and 0453 were started
this way and had to be handed to agents by hand.

## Where it comes from

`Scripts/bundle.sh` puts the resource bundles in `Contents/Resources/` (line 74)
and the command-line tools in `Contents/Resources/bin/` (lines 51–67). For the
app that is right: its executable is in `Contents/MacOS/`, so `Bundle.main` is
the app and `Bundle.main.resourceURL` is `Contents/Resources`. For a tool in
`Contents/Resources/bin/`, `Bundle.main` is that directory, and SwiftPM's
generated accessor looks for `Abydos_AbydosKit.bundle` beside the executable,
where there is none.

So it is a layout mismatch and not a missing file: `Abydos_AbydosKit.bundle` is
in the app, one directory up from where the tool looks.

## What still works, which is why nobody noticed

Measured against the installed copy at
`/Applications/Abydos.app/Contents/Resources/bin/abydos-backlog`:

- `--help`, `status`, `list`, `next`, `show`, `new`, `eta`, `spec check` — all
  fine. None of them reaches `Bundle.module`.
- `start 9999` fails cleanly with `There is no item 9999`, so it is not a
  start-up cost either.
- Only a `start` that gets far enough to launch the assistant crashes.

`grep Bundle.module Sources/AbydosKit` finds `SchemeLibrary`, `Mermaid` and
`DrawioRenderer`, none of which is obviously on this path — **so the first job is
to find what actually touches it**, with a backtrace rather than by reading.
`SWIFT_BACKTRACE=enable=yes` on the installed binary is the short way there.

## What it was: reading one setting

It is `SchemeLibrary`, and it is reached through the *permissions* the agent is
started with. The backtrace, from the top down:

    BacklogCommands.start                     BacklogCommands.swift:602
    BacklogRunner.start                       BacklogRunner.swift:180
    BacklogRunner.finish                      BacklogRunner.swift:208
    BacklogRunner.extraArguments              BacklogRunner.swift:230
    default argument of AgentLauncher.permissionArguments()
                                              ReviewSession.swift:305
    Settings.shared → Settings.init           Settings.swift:10, 84
    Appearance.name(family:mode:)             Appearance.swift:53
    Appearance.library → SchemeLibrary.shared Appearance.swift:42
    SchemeLibrary.bundledDirectory            SchemeLibrary.swift:21
    Bundle.module                             resource_bundle_accessor.swift:44 → fatalError

So: what an agent may do without asking is a setting; the first read of any
setting builds `Settings.shared`; that registers its defaults, one of which is
the appearance — a *scheme name*, which only the scheme library can spell; and
the shipped schemes are a resource of `AbydosKit`. Nothing about picking up an
item needs a colour, and the whole chain runs before `start` has printed a word.

Two things this explains that the item did not:

- **It only crashes for Claude Code.** `extraArguments` asks for permissions for
  `.claude` and for nothing else, so a backlog configured for `opencode` starts
  fine from the same binary. That is why it looked like "a `start` that gets far
  enough".
- **`make install-cli` is broken the same way.** The copy in `/usr/local/bin` has
  no bundle beside it either, so `abydos-backlog start` from the `PATH` died with
  the same line. Measured, before and after.

## What was done

`Bundle.module` is not used in this package any more. `ModuleResources`
(`Sources/AbydosKit/Support/ModuleResources.swift`) finds
`Abydos_AbydosKit.bundle` by looking in each place it could be and returns `nil`
rather than aborting when it is nowhere. It is the same shape as the two
hand-rolled searches that were already here — `MainWindowController.bundledChart`
and `LanguageRegistry.searchDirectories`, both written after `Bundle.module` took
something down — and `LanguageRegistry` now shares its list of places, so the
grammar queries are found from inside the app's `bin/` too.

The candidate it adds is the enclosing `.app`: walked up to from
`Bundle.main.bundleURL` rather than assumed to be one level, because the app's
own executable is in `Contents/MacOS/` and the tools are in
`Contents/Resources/bin/` — different distances from the same `Resources`.

`Start.command` is now computed when it is asked for instead of when the worktree
is made, which is what puts every question about the assistant *after* the caller
has printed the branch and the worktree. And `start` prints the directory and the
prompt whenever an agent does not start, from either cause.

## How it was proved

Not by installing: `/Applications/Abydos.app` is the app somebody is using, and
replacing it to test a command-line tool is not a trade worth making. So
`make build BUNDLE_ID=de.rnd7.abydos.item0464 PIN_UUID=0`, release and then
debug, and the resulting `build/Abydos.app` copied whole into a scratch
directory. The layout is the layout that matters —
`Contents/Resources/bin/abydos-backlog`, signed, inside a real bundle — and both
copies pick an item up end to end. The old installed binary was run against the
same throwaway project for the before, and it is the crash.

Also measured on the same project: a copy of the tool alone in a directory with
no bundle anywhere near it, which is what `make install-cli` produces. The old
one aborts, the new one starts the agent.

The item picked up was a throwaway: a scratch git repository with a backlog of
one item, made for this and deleted after. The assistant was a stand-in — a shell
script named `opencode`, first on the `PATH`, which writes its arguments to a
file — so no real agent was ever launched and no tmux server was touched. The
Claude Code path, which is the only one that crashed, was exercised with
`start 1 --print`: it prints the command it would run, and that command is built
by exactly the code that used to abort.

The app was never launched, so `Settings.migrate` never ran and the user's
settings were not reached. `abydos-backlog` reads and writes its own preference
domain — `abydos-backlog`, since the binary has no bundle identifier — not the
app's `de.rnd7.ideai`.

`make build` — release and debug — and `make test` green: 2381 tests in 349
suites in 30 seconds at load average 22.

An earlier run of the same suite, at **load average 65** with two other agents
building on this machine, failed two: `PseudoTerminalTests` waited 124 seconds
for output that a command produces in 0.35, and one `ContainerLSPLiveTests` case
disagreed about a URI. Both suites pass on their own, and both passed in the run
above. Worth writing down only because the numbers say which it was — a suite
that takes 124 seconds to fail is a suite that was starved, not a suite that is
wrong.

## Ruled out

- **`PACKAGE_RESOURCE_BUNDLE_PATH=…/Contents/Resources`** — worth knowing about
  but not a fix, and not verified against `start`. It was set while diagnosing
  this and proved nothing: every subcommand it was tried on works without it too.
  It is now honoured first by `ModuleResources`, for parity with the accessor it
  replaces, but nothing needs it.
- **Carrying a second copy of the bundle in `Resources/bin/`** — not done. It is
  23 MB of draw.io and 3.6 MB of mermaid duplicated inside one app so that a
  4 KB directory of colour schemes can be read, and `bundle.sh` would then have
  two places to keep in step.
- **A symlink from `Resources/bin/` up to the bundle** — not done, and the
  question of whether it survives signing was not answered, because it stopped
  being worth answering. It would also fix only the app, leaving
  `make install-cli` broken.
- **Not asking for the setting** — considered and rejected as *the* fix. The
  permissions really are a setting, and `Settings.shared` reaching a resource
  bundle is not wrong in itself; what was wrong is that the answer to "where are
  my resources" was `fatalError`. Cutting this one call would leave the next
  process that reads a setting from a tool to find the same landmine. The chain
  is unchanged and it now works.
- **Making `Bundle.module` work by name** — there is no supported way to make
  SwiftPM's generated accessor look one directory up; the generated file is not
  ours to edit and is regenerated on every build.

## Worth deciding

*Answered above: find the app, not carry the bundle and not stop asking. The
third point was done as well as the first.*

- ~~Whether the tool should carry the bundle or find the app.~~ Find the app.
- ~~Whether a tool in an app should reach for `Bundle.module` at all.~~ Nothing
  in this package reaches for it, and a test says so.
- ~~`start` should not crash when the agent cannot be launched.~~ Done.

## Steps

- [x] Find what on the `start` path touches `Bundle.module`, from a backtrace
- [x] Decide between carrying the bundle, finding the app, and not asking
- [x] Find the app: `ModuleResources`, and no `Bundle.module` left in the package
- [x] `start` says what happened rather than crashing, when the agent cannot be
      launched but the worktree was made
- [x] Tests: nothing to find is `nil`, both bundle layouts, the tool-inside-an-app
      path, and no source reaching for `Bundle.module`
- [x] The bundled tool, from a real `.app`, starts an item end to end
- [x] Write down here what was ruled out on the way
- [x] `spec/backlog.md` says what the project now does

The step above was written as "the installed tool, from `/Applications`". It was
done from a copy of the built `.app` in a scratch directory instead, because
`make install` replaces the app the user is working in. Same bundle, same
`Contents/Resources/bin`, same signature — see "How it was proved".
