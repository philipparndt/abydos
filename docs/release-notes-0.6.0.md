# Abydos 0.6.0

Eighteen commits since 0.5.0, and three of them are the same sentence:
**the app would not start.** If that was you, it is fixed, and the reason is
worth reading — it was not one fault but a chain, and each link was quiet.

The rest is a release about size. A work tree of seventy thousand untracked
files, a Maven reactor of a hundred and eighty-four modules, a checkout with
twenty-five thousand tracked files: the things that were pleasant on a small
project and unusable on a large one.

## The app starts again

**A build with no Metal toolchain shipped a bundle it was written to prevent.**
The block that compiles the 3D viewer's shader already knew the failure — its
own comment describes it — but had no failure path. Where `xcrun metal` cannot
run, the `&&` chain quietly produced nothing, there was no `else`, and the build
printed `==> Done`. `swift build` says `error: cannot execute tool 'metal'` and
exits 0, so nothing upstream noticed either. What shipped had `Shaders.metal`
present and `default.metallib` absent, and the renderer aborts the process on
that:

    Termination Reason: Namespace SIGNAL, Code 5, Trace/BPT trap: 5
    Fatal error: Failed to initialize Metal renderer: shaderLoadingFailed

**Then the session restored the tab that caused it.** So it died a second into
every launch, recoverable only by editing a file by hand.

Three changes, each of which alone would have been enough:

- A shader that does not compile now fails the build, names the remedy, and
  exits non-zero. `ALLOW_MISSING_SHADERS=1` carries on for somebody who never
  opens a model, and says in one sentence what that build will do if they ever
  do.
- gostl 0.23.2 compiles `Shaders.metal` at runtime where the library is absent,
  so a missing toolchain stops being fatal at all — which in turn makes failing
  the build too strict, and a missing toolchain is now a note rather than an
  error. A shader that will not *compile* is still fatal, because the runtime
  fallback would fail the same way, later, in front of somebody.
- A model that ended the last session is not rendered again unasked. The trap
  is a Swift precondition inside somebody else's code reached through SwiftUI —
  not catchable — so the answer is to decline to walk into it twice. A note is
  written before the render and cleared five seconds later; one found at startup
  means the last run did not survive that model. There is a "Show anyway" beside
  the reason, because the cause may since have been fixed and asking is the only
  way anybody finds out.

**And a signed app that the kernel refused.** `make install` put a bundle in
/Applications that died with `Namespace CODESIGNING, Code 2, Invalid Page` and a
crash report full of dyld frames and nothing about a certificate. `--sign "Apple
Development"` is a prefix match over the certificate *name*, and a keychain can
hold two certificates with identical names — renewing one without deleting the
old is all it takes. codesign refused as ambiguous, that refusal was a *warning*
printed before `==> Done`, and nothing verified afterwards. It signs by hash now,
falls back to a real ad-hoc signature, verifies with `codesign --verify --strict`,
and exits non-zero.

## And it stops freezing

**The git view on a large repository.** Opening it on a work tree with 69,829
untracked files took tens of seconds with nothing on screen to say so.
`--ignored` switches off git's untracked cache: with those flags git cannot
reuse a cached per-directory answer, so every filesystem event walked the whole
tree cold. Four consecutive runs took 6.4 s, 16.2 s, 59.7 s and 26.8 s — it
never warmed up, because there was no cache to warm. The same question without
them is a steady **0.11 s**.

Nothing is given up: a directory git collapses to `dir/` is one it collapsed
because nothing inside it is tracked, so those rows are coloured from the
directory's own entry — exact, not an approximation. What is ignored is still
read in full, on the schedule that question really has: when an ignore rule
changes.

**Switching projects held the main thread for 2,419 ms.** The window stopped
answering for that whole time, and the terminal stopped drawing with it. Two
directory walks, two deep, on the queue the keyboard shares — neither reading
anything of ours, so neither had a reason to be there. The switch measures
**34 ms** now, and the stall log says "project switch" where it used to say
"idle": a two-and-a-half-second stall with nothing to say for itself is the one
thing that log exists not to do.

**A crash and a flicker that were the same bug.** The branch pill flickering and
a segfault in `Project.loadGit` were one thing: `loadGit` was `nonisolated
async`, so it ran on the cooperative pool however main-actor its callers were,
and the repository watcher calls it on every change inside `.git`. Two threads
wrote the same `URL?` and the second release of it was a segfault. It is
`@MainActor` now, and a caller arriving while a load is out waits for that one
rather than starting another — thirty-two at once cost 28 ms against 59 ms for a
single.

## A file, by typing its name

There was no way to open a file by name. Not a slow way — none. Finding
`GitRepository.swift` meant walking the tree to it, or searching for text that
happens to be inside it.

Files now join the ranked list in the command palette beside projects and
branches, so `>` and `:` keep the meanings they had. A match in the file's own
name outranks one in a directory above it: `Git` finds `Model/Git.swift` before
everything inside `Sources/Git`.

The index is `git ls-files`, and one measurement decided that. On a work tree of
24,691 tracked files:

    git ls-files                                       24,691   0.03 s
    git ls-files --cached --others --exclude-standard   24,692   4.56 s
    the project walk, with its exclusions               25,564   3.05 s

The middle row is the surprise: asking git for untracked-but-not-ignored files
costs a hundred times more and finds one extra file, because to know what is
untracked git must walk the work tree. The project's own walk is the fallback
where there is no repository.

The first attempt at matching was four times slower than its own unit test
claimed — lower-casing every path per keystroke read 110–157 ms per character on
a real tree against 25 ms for synthetic ones. Prepared once as lower-cased UTF-8
and searched as bytes, it is 8.4 ms.

## A branch brought up to date without checking it out

`main ↓4` in the tree, with the work happening on a feature branch, and no way
to act on it. Advancing `main` was checkout, pull, checkout back: three
operations, a working copy touched twice, and a stash in the middle if anything
was uncommitted — all to move a ref to a commit already in the repository.

`git fetch . <upstream>:<branch>` does it in one. Nothing goes over the network
and no credential is wanted. The working copy and the checked-out branch are
untouched, which is the point and is what the test asserts.

Offered only where it really is a fast-forward, and a branch with its own
commits is told so with the count — "3 commits are on it and not on
origin/main" — rather than refused with a shrug.

## Two menus become pickers

**The branch pill.** "Takes very long to click it" turned out not to be about
the click: for the first ~780 ms of a project there is no pill at all, and the
menu returned without opening anything while the repository was unread. So a
click in that window did nothing, said nothing, and left somebody clicking a
gap. The pill reads `reading…` now and the popover opens whenever it is clicked,
showing "Reading branches…" until the list arrives.

The branches were sorted — by commit date, which from the outside is
indistinguishable from no order. Now: the current branch and the repository's
default pinned on top, then branches in no folder, then a section per folder,
each sorted by name with numbers read as numbers. Folders come from the *first*
slash, so `backup/feat/git` is a backup rather than filed beside the branch it
is a backup of.

**The run dropdown** offered each goal against each module it could run in —
goals × modules. On a reactor of 184 modules that is 683 rows for nine distinct
choices, four goals accounting for 676 of them, running off the bottom of the
screen under a scroll arrow in a menu that cannot be typed at. A goal is named
once now with a `184 places ›` chip, and the module is the second choice it is.
A goal in three places or fewer is not folded.

## Debugging through a wrapper script

Pointing a launch configuration at `./mvnw` got `'mvnw' is not a valid
executable` from LLDB — true, and about the wrong program. Nobody pointing a
configuration at `mvnw` wants to debug the shell; they want to stop on a
breakpoint in the Java it eventually starts.

A script is recognised by the two bytes at the front, never by its name. How you
ask for a JDWP port differs per wrapper and the three ways are not
interchangeable: `MAVEN_OPTS` for Maven; `--debug-jvm` for Gradle, because
`GRADLE_OPTS` reaches the *daemon* and suspending that hangs the build with the
debugger attached to the wrong JVM; `JAVA_TOOL_OPTIONS` for anything else with a
shebang.

Ten further faults sat between pressing Debug and a debugger attaching, all
found against a thousand-module Maven repository. The two that stopped it
outright:

- `DebugPort.isOpen` detected a listener by connecting and closing. On a JDWP
  port that *is* an attach — the JVM accepts, waits for the handshake, gets a
  close, and gives up on the session, after which the real debugger is refused.
  Polling five times a second, the probe was always first to the port. It asks
  by `bind` now, which touches nothing on the other side.
- A `file:` URI parsed with `URL(fileURLWithPath:)` reads as a relative path, so
  every classpath the language server returned was rejected as "an answer about
  another project" — and reported as an unfinished import, for a project whose
  import had finished half an hour earlier.

And a JVM refuses to start with two debug agents. A launcher script carrying its
own JDWP option in `MAVEN_OPTS` plus this app writing one into
`JAVA_TOOL_OPTIONS` are different variables and the same JVM, which said `Cannot
load this JVM TI agent twice`. The sweep is over all five variables a JVM
honours now — `MAVEN_OPTS`, `GRADLE_OPTS`, `JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`,
`JDK_JAVA_OPTIONS` — keeping everything that is not an agent, and naming the
variable each displaced option came from, since none of them appear in the
command line the run pane shows.

## Also

- **An emoji takes the two columns it is drawn in.** A build log full of ✅ drew
  each one clipped to half its width with the text after it a column to the
  left. The width table listed an arbitrary slice of the emoji planes, missing
  ✅ ❌ ❗ ✨ ⚡ ⭐ 🚀 🟩 and the rest. Not a longer list — asked of Unicode
  instead: a scalar whose default presentation is emoji is East Asian Wide,
  which is one line and every block, including ones added after it was written.
- **Staging works while a subproject is open.** `git status` reports paths from
  the work tree root; `git add` resolves them against the current directory. The
  panes ran git inside the subproject and handed it paths already measured from
  the root, so nothing could be staged, unstaged or discarded at all.
- **The dev pod carries Delve 1.27.1**, up from 1.26.2 — `pharndt/ideai-devpod:dev`
  and `:dev-go`. The `native` and `jvm` variants carry no Delve and are unchanged.
