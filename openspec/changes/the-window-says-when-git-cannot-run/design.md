## Context

Every git call in this application is one function: `GitRepository.run` spawns
`/usr/bin/git` with the caller's arguments, drains both pipes and answers a
`ProcessResult` of stdout, stderr and exit code. `GitBlob` spawns the same path
for one streaming case. `/usr/bin/git` is not git: it is Apple's shim, which
resolves the active developer directory and runs the git inside it — and when
it cannot, because Xcode's licence is unaccepted or no developer tools are
installed, it prints why to stderr and exits **0** with nothing on stdout.
Measured this morning:

    $ env -i PATH=/usr/bin:/bin /usr/bin/git --version >/dev/null 2>&1; echo $?
    0

So `GitForge.remoteURL` — `guard result.exitCode == 0`, then the trimmed
stdout, empty meaning "no remote" — answered `nil` for every project, and
`ProjectTrust.noteRemote(host: nil, …)` recorded each as *asked, no remote*.
Trust by host then had nothing to match. `refreshTrustBanner` put the trust
strip up over projects that would have been trusted, and the git pane read an
empty repository.

The window has one strip already: `TrustBanner`, hung at the top of the
content view with a height constraint of 0 or 30 and a top constraint that
takes the titlebar inset when it is up, so that `updateTopInsets` gives the
inset to exactly one thing.

## Goals / Non-Goals

**Goals:**

- The window says, in one line, that git cannot run and which command fixes
  it, the moment the first git call is refused.
- The strip goes away by itself when git runs again, without a relaunch, and
  trust by host comes back with it.
- No project is called untrusted on the strength of an answer git never gave.

**Non-Goals:**

- Running the fixing command from the app. `sudo xcodebuild -license accept`
  wants a password in a terminal, and an app that opens a terminal and types
  `sudo` into it is doing something nobody asked it to.
- Any change to what an untrusted project may do.
- Finding git anywhere but `/usr/bin/git`. Homebrew's git on the PATH is not
  what the rest of the machine uses, and a second git is a second set of
  answers.

## Decisions

### 1. Classified by stderr, at the one spawn site

`GitAvailability.classify(_ result: ProcessResult) -> Cause?` reads stderr for
the shim's two sentences — `You have not agreed to the Xcode license` and
`invalid active developer path` — and answers `.licenceNotAccepted` or
`.developerToolsMissing`. `GitRepository.run` calls `GitAvailability.shared.
note(result)` on every result it returns: a cause marks git as not running,
anything else marks it as running. `GitBlob`'s streaming path drops stderr
and is left out: it fetches one blob for a picture, and every project has
been through `run` before it is ever asked. Nothing the callers do changes; `remoteURL` still sees exit 0 and an empty
stdout, and still answers `nil`.

*Ruled out: the exit code.* It is 0. *Ruled out: probing once at launch.* The
licence can go unaccepted between two launches — an Xcode update while the
app is open — and a probe at launch would say "fine" for the rest of the day.
Every call is already a probe.

### 2. One strip, in the trust strip's place, and it cannot be dismissed

`GitAvailabilityBanner` is a sibling of `TrustBanner`: one line, the accent
colour the trust strip uses, the cause's sentence and its command in
monospace, and a *Copy Command* button. The window hangs it where the trust
strip hangs, and `updateTopInsets` treats "a strip is up" as either of the two.
When both would show, this one shows and the trust strip waits — see decision 4.

Its text per cause:

| Cause | Sentence | Command |
| --- | --- | --- |
| licence not accepted | git cannot run: Xcode's licence has not been accepted. | `sudo xcodebuild -license accept` |
| developer tools missing | git cannot run: no developer tools are installed. | `xcode-select --install` |

There is no close button. The trust strip can be put away because it names a
decision somebody may be about to make; this one names a machine that cannot
run git, and putting it away changes nothing about that. It goes when git
runs.

*Ruled out: a dialog.* It would interrupt a launch that restores twelve
tabs, and be gone by the time somebody wanted to read the command. *Ruled
out: a line in the git pane only.* The trust strip was the first thing seen
this morning, and the git pane the second; a message in the second place
would not have explained the first.

### 3. Asked again when the app comes back

`applicationDidBecomeActive` runs `git --version` through `GitRepository.run`
when availability says git is not running — one subprocess, only while the
strip is up. The result notes itself as decision 1 says, the strip comes down,
and `GitAvailability` tells its observers. There is no timer: the person fixing
this is in a terminal, and switching back to the app is the moment they want
the answer.

### 4. A remote that could not be asked was not asked

`ProjectTrust.noteRemote(host: nil, …)` is what the window calls when
`remoteURL` answers `nil`; it marks the project *asked, no remote*, which is
what makes the strip go up. The window checks `GitAvailability.shared.isRunning`
before noting: while git is not running the project is left **unasked**, so
`isDecided` is false and `refreshTrustBanner` puts no strip up. When
availability comes back, `ProjectTrust.shared.forgetUnaskedRemotes()` is not
needed — nothing was recorded — and the window re-runs the remote lookup for
its current project, the same `Task` `load(project:)` runs.

*Ruled out: recording the failure as a third state in the trust store.* The
store is about what somebody decided; git not running is about the machine and
lives in `GitAvailability`, and one place per fact.

### 5. Proving it without breaking the machine

`--git-unavailable licence|tools` makes `GitAvailability` behave as though
every result carried that cause, so a driven run shows the strip and prints it
under `--trust-report` — `GIT: strip=[…]` beside the trust lines — and a
project with a trusted remote prints `trusted=false banner=[]`: no trust strip
over an unasked project. The classification itself is a kit test over the two
sentences as the shim prints them, and over an ordinary failure — `fatal: not
a git repository`, exit 128 — that must *not* classify.

## What was measured, 2026-09-15

Four driven runs on the built app as `de.rnd7.abydos.gitshim` with an
unpinned UUID, load averages 5.6–6.6; nothing here is timed. The scratch
repository's `origin` is `https://github.com/philipparndt/scratch-trust.git`,
which the trust store on this machine covers by owner. A driven run reads that
store and writes nothing to it.

    --git-unavailable licence
    TRUST: trusted=false banner=[no banner]
    GIT: strip=[git cannot run: Xcode's licence has not been accepted. sudo xcodebuild -license accept]

    --git-unavailable tools
    TRUST: trusted=false banner=[no banner]
    GIT: strip=[git cannot run: no developer tools are installed. xcode-select --install]

    (git running)
    TRUST: trusted=true banner=[no banner]
    GIT: strip=[no strip]

    (a folder that is not a repository)
    TRUST: trusted=false banner=[plain-folder-1 is not trusted — nothing in it runs by itself, and its environment reaches nothing.]
    GIT: strip=[no strip]

The first two are decision 4 in one line: `trusted=false` with **no trust
strip**, because the project was never recorded as asked. The last is the
ordinary failure that must not classify — `fatal: not a git repository` at
exit 128 — and the trust strip over it is the one that was always there.

The morning's own case was measured before the fix rather than after: the
shim's exact sentence at exit 0 is in `GitAvailabilityTests`, taken from the
terminal at 07:14, and the licence was accepted before this was built.

**Where the signature landed.** `GitAvailability` is a class with a lock
rather than an actor, because `GitRepository.runSync` notes results from a
global queue and the window reads `cause` synchronously while laying out a
strip; observers are told on the main queue only when the answer changes. The
git strip shares the trust strip's constraints — same top, same height — so
the split view below hangs off one edge whichever is up, and `updateTopInsets`
asks one question, `stripIsUp`. The remote lookup moved from `load(project:)`
into `askRemote(for:)` in the trust file, where the availability guard and the
re-ask on recovery both read it.

## Risks / Trade-offs

- **Apple rewords the shim** → the sentence is not recognised and the window
  is back to today; the two strings are the whole of the coupling and are
  held in one place with the tests. Nothing else in the app depends on them.
- **A licence accepted while the app is in front** → no `didBecomeActive`;
  the next git call of any kind notes success and takes the strip down, so the
  strip lags by one action rather than a relaunch.
- **stderr noise from a real git** → a working git never prints these
  sentences, and the classification requires them; a warning beside real
  output classifies as nothing.

## Open Questions

None.
