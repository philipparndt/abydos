## Why

The maintainer, 2026-09-15: *"seems like I have to trust each and every project
again and it is no longer possible to open the git pane on any project."*

Xcode 27.0 had been installed overnight and its licence not yet accepted. In
that state `/usr/bin/git` — the shim every git call in this application goes
through — runs nothing. It prints

    You have not agreed to the Xcode license agreements. Please run 'sudo
    xcodebuild -license' from within a Terminal window to review and agree to
    the Xcode and Apple SDKs license.

to stderr and **exits 0**, with nothing on stdout. So every git call looked to
this program like a success with an empty answer: the remote lookup that trust
by host relies on found no remote, so every project trusted by
`github1.vg.vector.int` or `github.com/philipparndt` asked to be trusted again
— three folders were trusted by hand between 06:53 and 06:56 before the cause
was found — and the git pane had nothing to show. Nothing in the window said
why. The cause took a session of reading logs to find, and the fix was one
command.

The sibling failure has the same shape: with no Command Line Tools and no
Xcode, the shim answers `xcrun: error: invalid active developer path` and
macOS puts up an install prompt of its own. Both mean *git cannot run on this
machine*, and both are answered by a command a person types once.

There is no originating `.abydos/backlog` item: this comes from the report
above.

## What Changes

- **One place classifies every git result.** `GitRepository.run` — the choke
  point every call already goes through — recognises the
  shim's refusals by what they say on stderr, since the exit code says nothing,
  and tells a shared `GitAvailability` that git cannot run and why. A result
  that came from git itself, exit code whatever it is, marks git as running
  again.
- **A strip across the top of every window**, the shape of the trust strip
  and in the same place, saying *git cannot run: Xcode's licence has not been
  accepted* — or that the developer tools are missing — and carrying the
  command that fixes it, with a button that copies it. It stays until git runs
  again and goes by itself when it does; it cannot be dismissed, because it
  names something that is wrong with the machine and not with the project.
- **The answer is asked for again when the app comes back.** Becoming active
  runs one `git --version`, so accepting the licence in a terminal and
  switching back takes the strip down without a relaunch — and the remotes
  that were asked while git was refusing are asked again, so trust by host
  comes back with it rather than after the next launch.
- **The trust strip does not go up while git cannot run.** A project whose
  remote could not be asked is undecided, not untrusted; the strip that says
  *untrusted* over a project that would be trusted if git could answer is the
  misdirection that cost this morning.

## Capabilities

### New Capabilities

- `git-availability`: what the window says when git cannot run on this
  machine, how that is detected, and how it is found to be working again.

### Modified Capabilities

- `project-trust`: a project whose remote could not be asked because git
  cannot run is undecided rather than untrusted, and is asked again when git
  runs.

## Impact

- **AbydosKit**: `Git/GitRepository.swift` (the classification at the one
  spawn site), a new `Git/GitAvailability.swift` (the state, the two causes,
  the message and the command for each, the re-check), `Project/ProjectTrust`
  (forgetting the remotes asked while git was refusing). Tests for the
  classification and the messages.
- **AbydosApp**: a `GitAvailabilityBanner` beside `TrustBanner`, hung in the
  window where the trust strip is and sharing its inset rule in
  `updateTopInsets`; the re-check on `applicationDidBecomeActive`;
  `refreshTrustBanner` reading the availability first.
- **Driving**: `--git-unavailable <cause>` makes the run behave as if the shim
  had refused, and `--trust-report` prints the strip's text, so the claim can
  be checked without breaking the machine's Xcode.
