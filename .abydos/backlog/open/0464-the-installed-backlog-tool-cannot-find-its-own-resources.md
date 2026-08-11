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

## Ruled out

- **`PACKAGE_RESOURCE_BUNDLE_PATH=…/Contents/Resources`** — worth knowing about
  but not a fix, and not verified against `start`. It was set while diagnosing
  this and proved nothing: every subcommand it was tried on works without it too.

## Worth deciding

- **Whether the tool should carry the bundle or find the app.** A copy beside the
  executable is the obvious fix and means two copies of the same resources in
  one app. A symlink from `Resources/bin/` up to the bundle is one file and no
  copy, but it is a symlink inside a signed bundle, which is worth checking
  against the notarisation step before choosing it.
- **Whether a tool in an app should reach for `Bundle.module` at all.** The thing
  it is reaching for may not be needed on this path, in which case the fix is to
  stop asking rather than to make the answer available.
- **`start` should not crash when the agent cannot be launched.** Whatever the
  resource turns out to be for, a worktree that was made and an item that was
  moved deserve a sentence saying the agent was not started and how to start it
  by hand. That is worth doing even if the bundle question is answered another
  way, because it is the difference between a bad afternoon and a message.

## Steps

- [ ] Find what on the `start` path touches `Bundle.module`, from a backtrace
- [ ] Decide between carrying the bundle, finding the app, and not asking
- [ ] `start` says what happened rather than crashing, when the agent cannot be
      launched but the worktree was made
- [ ] The installed tool, from `/Applications`, starts an item end to end
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
