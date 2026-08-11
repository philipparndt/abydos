# 473. The live container tests leave a container behind, and it breaks the next run

`ContainerLSPLiveTests` leaks a container per run. Three separate agents reported
it today as an aside — "cleaned up the ones my runs left but did not fix the leak"
— and it was treated as untidiness. **It is not untidiness. It fails the suite.**

Measured today, on one commit:

- With `abydos-lsp-jdtls-75631-23` left behind by a test process that had died
  two hours earlier, `aServerInAContainerAnswersAboutFilesOnThisMachine` failed
  its jdtls case on `diagnosed.uri == fileURI` — **twice in a row** — and the
  suite took **124 s** instead of 31.
- The same container removed, nothing else changed: the suite passed in 56 s, and
  passed again afterwards.

So a stale container of the same tool does not merely take memory: something finds
it and answers about the wrong paths. Whether that is the app's own reuse-by-name
or the runtime handing back an old one is the first thing to find out, and it may
be a **bug in the reuse rather than in the tests** — which would make this an item
about the app and not about hygiene.

> **The paragraph above is wrong, and so are the two merge commits on `main` that
> repeat it.** It was measured honestly and it does not survive being reproduced
> deliberately: with a stale container present the suite passes and with none it
> fails. Read *What it turned out to be*, below, before acting on anything here.
> The leak is real; the connection to the failure is not.

## What is known about the sweep

There is already a sweep, and it works — one agent saw the app print `Removed 4
container(s) left by an earlier run`. But it spares containers whose owning
process is still alive, which is right, and that is why four of them survived
today: `abydos-lsp-jdtls-{53519,64145,66987}-23` started between 14:29 and 14:34
by processes that were still running. The names carry the owning pid, so the rule
is sound and the leak is that a *finished test run* does not clean up after
itself before its process exits.

## Why it is worth fixing rather than living with

Every one of today's five agents had to reason about container state, and two of
them lost time to a red suite that was not theirs. A leak that only costs disk can
wait; a leak that makes a different test fail teaches everybody to distrust the
suite, which is the expensive kind of failure.

## Worth deciding

- **Where the cleanup belongs** — a suite-level teardown, a `deinit`, or the
  existing sweep made to run at the *start* of a live-container test rather than
  at app launch. The last one is the smallest and covers a crashed run too, which
  a teardown cannot.
- **Whether the URI failure is the tests' fault at all.** If the app reuses a
  container by name and gets one from a dead process, the sweep is a workaround
  for a reuse bug. Find out before choosing where the cleanup goes.
- **What a leaked container costs when nothing fails**, so the sweep's own
  reporting says something useful — four of them is 4 GB of the runtime's memory
  by the figures in `container ls`.

## What it turned out to be

**The stale container was a coincidence, and the premise above is wrong.** The
first thing this item asked for was a deliberate reproduction, and the
reproduction inverted it. Measured on this branch, one commit, nothing else
changed, `--filter ContainerLSPLiveTests`:

- **Nothing stale on the machine**: the jdtls case *failed* on
  `diagnosed.uri == fileURI`, in 15.8 s.
- **A stale `abydos-lsp-jdtls-92786-6` present**, left by the run above: the same
  case *passed*, in 14.8 s.

So it is the other way round from every report today, and both readings were
somebody changing one thing and watching a coin come up differently.

What the failure actually is, from the values swift-testing printed:

    diagnosed.uri → "file:///…/ideai-java-tests-CD04D0C6-…"
    fileURI       → "file:///…/ideai-java-tests-CD04D0C6-…/src/Probe.java"

The URI that arrived is the **project directory** — no filename. jdtls's Eclipse
import publishes a diagnostic against the project folder before it publishes one
against any file in it, `Diagnosed` kept whichever arrived first, and the test
required that first one to be the file just opened. That is a race with roughly
even odds on jdtls and no odds at all on the other five, whose first word is about
the file. It is not a mapping bug: the directory URI came home correctly, which is
the thing this test exists to check.

The test now waits for a diagnostic **about the opened file** and keeps every URI
that arrived, so a failure says what the server did name. The claim it makes is
stronger than the one it replaced: *every* `file:` URI the server chose is under
the project, rather than whichever one happened to arrive first being exactly the
file.

### Neither reuse-by-name nor the runtime

- **The app cannot reuse a language server's container.** The name is minted per
  launch — `ToolContainers.mint("lsp-\(command)")`, so `abydos-lsp-jdtls-<this
  pid>-<n>` — and a name carrying another process's pid can never be produced
  again. `claim`, which does deliberately take a name over from a dead run, is
  only used by the kept PlantUML server and by devcontainers, whose names are
  stable on purpose. No LSP path calls it.
- **The runtime does not hand one back either.** Asked to `run` under a name that
  exists, Apple's `container` answers `Error: container with id
  abydos-lsp-jdtls-17228-23 already exists`. It refuses; it does not reuse.
- **Proved rather than argued.** With `abydos-lsp-jdtls-17228-23` deliberately on
  the machine — the exact shape of the leaked names, and holding `alpine:3` rather
  than jdtls, so anything that found it by name would have got a shell instead of a
  language server — the suite is green and the jdtls case answers about its own
  project. Its owning process was alive, so the sweep spared it and it was up for
  the whole run.

### The leak itself, which is real

`LSPClient.stop()` posts the container's removal to a background queue and
deliberately does not wait — closing a project should not pause on a runtime. In
the app `atexit` covers what that misses; the test bundle has no such handler, and
a test process exits within milliseconds of its last test. So **the last container
a run starts is the one that leaks**, and jdtls is the last of the six probes,
which is why every leftover found today was `abydos-lsp-jdtls-*`. Confirmed
directly: after one run, `abydos-lsp-jdtls-92786-6` was still up with no process
92786 on the machine.

### One removal was not always enough

Worth knowing before somebody trusts a single `rm --force` again. On a machine
already holding fifteen containers, and with another suite running beside this one,
a full run left `abydos-lsp-jdtls-<its pid>-25` up *having sent the removal* — the
runtime asked to remove a container it was still in the middle of starting. The
same removal takes 0.2 s on a quiet machine and was measured at 3.1 s on a busy
one, which is not a wide margin under the app's ten-second deadline either. So the
test asks, checks with an `inspect`, and asks again up to three times, and then
**expects** the container to be gone rather than hoping: a run that quietly fails
to clean up is exactly this item, and what made it cost five agents a day each is
that there was no failing test anywhere.

### Why they piled up rather than being swept

The sweep at launch asked `ContainerRuntime.discover`, which honours the
preference — and on this machine the docker command line is installed with its
daemon deliberately stopped, so `automatic` names docker, `docker ps -a` fails, a
listing that did not succeed reads as "nothing to remove", and **every container of
ours was in Apple's runtime, which nothing ever looked at.** That is the app half
of this item, and it is why five agents each found leftovers and cleaned them by
hand. Cleaning up now asks every runtime installed; choosing where to *start* a
tool still honours the preference exactly.

### What one costs when nothing fails

On Apple's runtime a container is a virtual machine: `container ls` reports **1024
MB and 4 CPUs each**, held whether the server inside is doing anything or not.
Fifteen of them were on this machine by the end of the afternoon, from branches
that do not have this fix — fifteen gigabytes of the runtime's memory to hold six
idle language servers nobody is talking to. The *time* cost is smaller than it
looked: the filtered suite is 15–20 s with one present and the same without, the
whole suite 28 s, and the 124 s against 31 s in the report above was not
reproducible in either direction. Disk is nil — the image is shared and a stopped
container holds a few megabytes of layer.

The sweep's line now names the runtime it removed from, which is the question
somebody reading it actually has, and not how much memory came back. Asking for
that means `container ls --format json` per sweep and a second answer to parse, for
a number that is the runtime's default in every case here — worth having only if
somebody is ever surprised by the figure rather than by the count.

### One thing the pid in a name cannot survive

A container is stale exactly when the process in its name is gone, and macOS
recycles process ids. Of the fifteen above, five named `…-30748-…` were spared by
every sweep because pid 30748 had been handed to a `swift-frontend` since: the name
says the owner is alive, the owner is somebody else entirely, and nothing here can
tell the difference. Left alone rather than guessed at — a sweep that decided a
*live* process was not really the owner is the one mistake in this area that costs
somebody their running server, which is the whole of 0435. Cheap to live with now
that a run cleans up after itself, and if it ever matters what it wants is the
container's start time compared against the process's, not a cleverer reading of
the pid.

## Ruled out

- **A shared Eclipse workspace between runs.** `ToolImages/jdtls/Dockerfile`
  passes no `-data`, so the launcher's default puts the index inside the container,
  and jdtls has no `outside` directories — only kmp-lsp does. Nothing about one
  run's workspace can reach the next.
- **A shared project directory.** `JavaTestDirectory.make()` is
  `ideai-java-tests-<UUID>` per call, so two runs never mount the same host path.
- **`ToolContainers.removeAll()` in the test bundle**, which would be the obvious
  way to catch every exit. It is forbidden, by a test, for a good reason
  (`ContainerCleanupTests`, 0435): it takes containers a suite running beside this
  one is in the middle of using. A test removes the containers it started, by the
  names it noted, and that is what this now does.
- **A `deinit` on the suite.** swift-testing makes a fresh suite value per test
  case and a `deinit` runs no earlier than a `defer`; neither runs at all for the
  exit that leaves a container, which is `run-tests.sh` killing a run for outliving
  `TEST_TIMEOUT`.
- **An unnarrowed sweep at the start of a live test.** It would remove
  `abydos-probe-sweep-<a pid the test declared dead>-1` out from under
  `theSweepTakesWhatAnEarlierRunLeft`, running beside it in the same bundle —
  trading a coin toss on jdtls for a rarer one somewhere else. The sweep in the
  tests considers language-server roles only, and that test now also checks that
  narrowing.

## Estimate

2026-08-11 19:49 — about half an hour left

## Steps

- [x] Reproduce it deliberately: leave a container, run the suite, watch the
      jdtls case fail — and it passed with one present and failed with none, which
      is the opposite of the report
- [x] Find out whether the failure is reuse-by-name or the runtime, and say which
      — neither: a race in the test between jdtls's project-level diagnostic and
      the file's
- [x] Wait for the diagnostic about the file rather than the first one to arrive,
      and check every URI that came back rather than one
- [x] Clean up where a crashed run is covered too, not only a tidy exit — the
      container this test started is removed and waited for, and what an earlier
      run left is swept on the way *in*
- [x] Check the removal rather than assume it, after one run under load left a
      container behind with `rm --force` already sent
- [x] Sweep every runtime installed rather than the preferred one, which is why
      the leaks were never swept on this machine
- [x] The suite green with a stale container present — the whole of it, 2451 tests
      in 355 suites, four times over, with `abydos-lsp-jdtls-<a live pid>-23` up
      throughout and thirteen more leftovers on the machine at the start of one of
      them. Nothing left behind by any of the four. The only red anywhere in them
      is `MermaidLiveTests.drawingIsFastEnoughToDoWhileSomebodyTypes`, which is
      0472's and fails under the load the suite makes for itself
- [x] Write down here what was ruled out on the way
- [x] `spec/tool-images.md` says what the project now does — the reuse did not
      change, the cleanup did, and neither was in the spec at all
