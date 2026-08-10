# 428. Work at the scale of a five-hundred-bundle project

The app is to be used on a Java/RCP product at work: **around 500 Maven bundles
and 500,000 to 700,000 lines**. The goal is not "it opens" — it is that it feels
fast at that size. Nothing in this repository has ever been opened at that scale,
and every number in the performance suite comes from a synthetic 100,000-line
file rather than from a real project with half a million lines spread across
hundreds of modules.

So the first work is not optimisation. It is a corpus and a baseline, because
"ultra fast" without a number is an adjective.

## The corpus

**Eclipse Platform** is the near-exact match, and matters because it is the same
*shape* rather than merely the same line count: RCP, built with **Tycho** (Maven
for OSGi), hundreds of bundles by construction.
`eclipse-platform/eclipse.platform.ui` is a few hundred bundles on its own; with
JDT and PDE alongside it the aggregator is in the right order of magnitude.

- **Eclipse Papyrus** or **Sirius** — RCP and Tycho, smaller. The fast inner
  loop: if something is slow there it is hopeless on the Platform, and a
  measurement takes minutes rather than an afternoon.
- Rejected, with the reason, so nobody proposes them again: **Apache NetBeans**
  is larger (~1.5M lines) but its module system is not Maven, so it exercises
  the wrong build path; **Elasticsearch** and **Kafka** reach the line count with
  Gradle and few modules, which is the wrong problem — they are good corpora for
  raw editor and index load and bad ones for the 500-bundle question.

Two corpora, then: Papyrus for the loop, Platform for the real number.

## What to measure, before changing anything

Each of these wants a number on the two corpora and on a small project for
contrast:

- **Time to a window** and, separately, **time to something usable** — they are
  not the same, and the second is what somebody feels.
- **Time until Java answers** — completion, go-to-definition — which is jdtls
  indexing and is likely to dominate everything else.
- **Memory**, ours and jdtls's, at rest and after an hour.
- **Keystroke latency** in a file in a large bundle, which is the thing that
  makes an editor feel cheap when it is wrong.
- **`git status` time** on a repository that size.
- **Filesystem events per build**, and what the tree does with them.
- **Search**, first result and all results.

The suite measures processor time properly as of 0416, so the machinery is
there; what is missing is a harness that opens a real project and reports these.

## What will hurt first, from reading the code — to be confirmed, not assumed

- **jdtls at that scale is most of the answer.** Its own indexing of 500 bundles
  is minutes and gigabytes, and much of "fast" will be about what it is asked and
  when — not about our code. Related: 0427, servers that are not reaped and run
  the wrong toolchain.
- **`FileNode.read` sorts every directory** and `handleFilesystemChange`
  re-reads every expanded directory on each event. A build in 500 bundles
  touches thousands of paths.
- **`git status` on every filesystem change.** Already coalesced — one at a time
  with at most one queued — which was enough for this repository and will not be
  at that size.
- **Whatever the editor does per keystroke**, which is measured today only on one
  large file rather than in a large project.

## Worth deciding

- Whether the corpus is vendored, cloned by a script, or expected beside the
  checkout. It is gigabytes; the examples repository is the precedent for "beside
  the checkout", and the screenshot harness already assumes that shape.
- Whether these measurements run in CI or by hand. They take minutes and need a
  large checkout, so probably by hand with the numbers written down here — the
  point is a baseline that can be compared against, not a gate.

## Steps

- [x] A script in the repository that clones the corpus beside the checkout,
      shallow, and says what it got
- [x] Say what the corpus actually is — bundles, Java lines, bytes on disk —
      rather than what the item guessed it would be
- [x] The app can say when its window came up and when the tree was usable,
      because no stopwatch outside the process can tell those apart
- [x] A harness that opens a project, takes the numbers, and prints the load
      average beside every one of them
- [x] Baseline: time to a window and time to something usable, on all three
- [x] Baseline: `git status`, cold and warm, on all three
- [x] Baseline: what one project open costs the language-server scan, after 0437
      made it one listing per directory rather than one per definition
- [ ] Baseline: time until Java answers, and what jdtls costs in processor time
      and memory beside what we cost
      — **not reached.** jdtls's memory and processor time are below; when it
      first *answers* is not, and the reason is the finding at the top of "What
      the numbers say": nothing measured here got to a quiet enough machine to
      ask it. See "What was not reached".
- [x] Baseline: keystroke latency in a file in a large bundle
- [x] Baseline: search, first result and all results
- [x] Baseline: filesystem events during a build, and what the tree does with
      them now that `loadedNode(for:)` stops at the first closed door
- [x] Write down what was ruled out on the way, and what the numbers say is
      worth attacking first
- [ ] The spec says what the project now does
      — **not being done, deliberately.** Nothing a user of the program can see
      changed: what landed is a corpus script, a test suite and two driver flags
      (`--report-open`, `--report-typing`). The app already carries something
      like a hundred and fifty such flags and none of them is in `spec/`, for
      the same reason `make screenshots` is not: the spec says what the program
      does, and this is how the program is measured. The findings below are
      where the next items come from, and those will carry deltas.

---

## What the corpus turned out to be

`Scripts/corpus.sh`, shallow, into `~/dev/abydos-corpus`. Both open questions
answered the way `make screenshots` already answers them for the examples
repository: beside the checkout, and by hand rather than in CI.

    platform  1022 bundles  45,772 .java  7,484,576 lines  763M   (7 repositories)
    sirius     106 bundles   8,307 .java  1,636,121 lines  313M

A bundle is a directory with an OSGi manifest naming a symbolic name, not a
`pom.xml`: Tycho builds most of these pom-less, and counting poms said 104 where
there are 1022.

Worth saying plainly, because it changes how the numbers should be read: the
Platform corpus is **larger than the product it stands in for** — 1022 bundles
and 7.5M lines against the item's 500 and 500–700k. It is a ceiling, not a
match. Sirius, at 106 bundles and 1.6M lines, is nearer the line count and well
under on bundles. The real thing sits between them.

Two repositories the earlier clone had taken are gone from the list:
`eclipse.platform.resources` and `eclipse.platform.text` were folded into
`eclipse.platform` and now hold a README each.

## The numbers

**Conditions.** A ten-core machine. Every reading carries its own load average
and each says which clock it is on. The machine was never idle — the user's own
Safari, an OrbStack VM and an installed Abydos put the floor at about 6 to 7,
which is 0.7 per core and comfortably under the 4.0 that `MachineLoad` treats as
too busy to time. Nothing else of this work ran during a measurement: builds and
`make test` were taken outside every window below. Where a load average above 10
appears it is **the app under measurement causing it**, which is the subject
rather than the noise, and is the finding.

The engine numbers are a release build under `swift test --no-parallel`
(`ScaleLiveTests`); the window numbers are the release `.app` driven by
`Scripts/scale.sh`.

### The engine, at load 6.6 (0.7 per core)

| | platform | sirius | this repository |
|---|---|---|---|
| tree: list the root | 5.4 ms wall / 2.6 cpu | 2.2 / 1.0 | 0.6 / 0.6 |
| tree: walk all of it | **4835 ms wall / 3979 cpu** | 1385 / 1115 | 1190 / 1040 |
| …which is | 22,680 listings, 93,969 nodes | 6,017 / 26,190 | 3,848 / 23,484 |
| language server scan | 27 ms wall / 24 cpu, 94 listings | 33 / 26, 135 | 4.4 / 4.4, 31 |
| `git status` cold / warm | no repository at this root | 380 / 231 ms | 24 / 22 ms |
| `git status`, platform.ui | 666 / 314 ms | | |
| search "public", first / all | **1434 / 1603 ms** | 441 / 537 | 177 / 607 |

Taken with `make scale`, which is `SCALE=1 swift test -c release --no-parallel
--filter ScaleLiveTests`. It has to be asked for rather than merely possible,
which the other live tests are: walking 22,680 directories of Eclipse is visible
to `FileNodeReloadTests`, which zeroes the process-wide
`FileNode.directoryReadsForTesting` and then asserts it is still zero. Beside
this suite that test fails on a claim about its own tree that this one had
quietly added to — `LanguageServers.DirectoryIndex` argues exactly this in a
comment and keeps its count on the index; the tree's counter is older and does
not. Discovered by breaking it, which is the only way anybody was going to.

A second run of the same suite, at load 5.7, agrees on everything except
`git status`: 105 / 89 ms on `platform.ui` and 176 / 144 ms on Sirius against
the 666 / 314 and 380 / 231 above. The difference is the operating system's page
cache, not the repository — the first run was the first time those objects had
been read on this machine. Both numbers are worth keeping and they answer
different questions: **666 ms is what opening a project you have not touched
today costs**, and 105 ms is what the tree pays on every filesystem event
thereafter.

### Opening a window

Wall clock from the kernel's `p_starttime`, so dyld's mapping of the app is
inside the number, where the person waiting for the window experiences it.

| | platform | sirius | this repository |
|---|---|---|---|
| tree listed | 215 ms | 219 ms | 201 ms |
| language servers scanned | 282 ms | 245 ms | 207 ms |
| window ordered front | 848 ms | 538 ms | 362 ms |
| window drawn | **1367 ms** | 789 ms | 550 ms |
| tree coloured (`git status` applied) | never — no repository | **1438 ms** | 637 ms |
| tree rows at rest | 477 | 294 | 51 |
| memory at 5 s / 30 s / 90 s | 364 / 528 / **641 MB** | 235 / 279 / 391 MB | 70 / 70 / 70 MB |
| our processor time by 90 s | **758,637 ms** | **728,722 ms** | 2,288 ms |
| load average at 90 s | **124** | **117** | 7.3 |
| watcher batches / paths by 90 s | 228 / 705 | 253 / 1279 | 2 / 2 |
| directories the tree re-read | **1** | **0** | 0 |

Time to a window and time to something usable really are different numbers, and
the second is the larger: on Sirius the window is there at 789 ms and the tree
is not coloured until 1438 ms. On the Platform aggregate the second number does
not exist at all, which is worth more than a slow one — there is no repository
at the root of nine sibling clones, so nothing ever colours that tree.

### Keystrokes, in a file in a large bundle

200 presses, timed one at a time on the main thread, at 90 seconds in.

| | file | wall median / p90 / worst | cpu median / p90 / worst |
|---|---|---|---|
| platform | `TextViewer.java`, 5,872 lines | 9.25 / 9.50 / 10.94 ms | 9.22 / 9.45 / 10.07 ms |
| sirius | `ViewpointPackage.java`, 3,680 lines | 5.61 / 5.90 / 7.02 ms | 5.58 / 5.80 / 6.01 ms |
| this repository | `LSPClient.swift` | 17.12 / 40.99 / **125.11** ms | 7.20 / 9.01 / 10.51 ms |

Two things here, and the second is the more interesting.

The processor cost of a keystroke tracks the **file**, not the project: 5.6 ms in
a 3,680-line Java file, 9.2 ms in a 5,872-line one, and 7.2 ms in a Swift file
in a project with nothing else going on. That is good news for the 500-bundle
question — a large project does not by itself make typing expensive.

But 9 ms is not a small number. A frame at 60 Hz is 16.7 ms, so a keystroke in a
large Java file eats over half of one. Set that beside `PerformanceTests`, which
reports **0.016 ms** per keystroke on a 100,000-line document: the suite's figure
is `TextDocument` alone, with no view, no highlighter running behind it, no
language server to tell and no gutter to re-mark, and it is out by a factor of
about five hundred from what the same key costs in the real editor. The item
suspected the suite was measuring the wrong thing; it is.

The third row is the one to be careful with. This repository's *wall* figure is
the worst of the three while its processor figure is the middle one — the gap is
sourcekit-lsp's answers landing on the main queue between keystrokes. On the
corpora the wall and processor figures are the same to two decimal places, and
that is not the app being calmer there: it is that the eight cores it is burning
(below) are burning somewhere other than the main thread.

## What the numbers say is worth attacking first

### 1. Opening a Tycho project makes the app spin at eight to nine cores, indefinitely

By far the largest thing here, and it was not on the item's list of suspects.

Ninety seconds after opening either corpus the app has used **759 seconds of
processor time on the Platform and 729 on Sirius** — around 8.4 cores, from the
first five seconds and not stopping — while this repository uses 2.3 seconds over
the same span. Resident memory climbs with it: 364 MB at five seconds, 641 MB at
ninety, still rising. The machine's load average goes from 7 to over 120, and
that load is the app.

It is not `git status` and not the tree. The Platform aggregate has no repository
at its root, so `git status` never runs there — its reaped-children total is 571
ms against Sirius's 5,871 — and the burn is identical on both. The tree re-read
**one** directory on the Platform and **none** on Sirius across 228 and 253
watcher batches, so `loadedNode(for:)` is doing exactly its job and is not it
either.

A profile names it:

    MainWindowController.refreshRunConfigurations()
      → RunConfigurationDiscovery.discover(in:)
        → RunConfigurationDiscovery.javaMainClasses(in:)
          → JavaTooling.mainClasses(in:limit:)
            → JavaTooling.mainMethodLine(in:isKotlin:)

`navigator.onFilesChanged` calls `refreshRunConfigurations()`, and
`handleFilesystemChangeMarked` calls `onFilesChanged?()` **first, before every
early return** — deliberately, so the staging view hears about edits in
directories the tree has not expanded. `refreshRunConfigurations` then throws a
whole-project walk onto `DispatchQueue.global(qos: .userInitiated)` looking for
Java classes with a `main` method, reading files as it goes. There is **no
coalescing on that path at all**: `refreshGitStatus` next door is careful — one
at a time with at most one queued — and this one is not. 228 filesystem batches
in ninety seconds is 228 concurrent walks of 45,772 Java files, piling onto a
concurrent queue that answers by making more threads.

And the events are not idle chatter: jdtls importing a Tycho reactor writes
`.project`, `.classpath` and `.settings` into every bundle it touches, so opening
the project *is* what generates them. The app makes its own storm and then
answers each clap of it with a full-project scan.

The item worried about the coalesced `git status` on every filesystem change.
The uncoalesced full-project Java scan standing right beside it is three orders
of magnitude worse and nobody had looked at it, because on this repository — 51
tree rows and no Java at all — it costs nothing and finishes instantly.

Deliberately not fixed here. The item says the first work is not optimisation,
and this wants a proper decision about coalescing and about whether run
configurations should be discovered from a filesystem event at all rather than
a hurried patch inside a measurement item.

### 2. Search shows nothing for a second and a half

1434 ms to the first result on the Platform, against 177 ms here. The shape says
what it is: the run matched 500 files having scanned only 721, so almost all of
that time was spent **before the first file was read**. `ProjectSearch.search`
calls `collectFiles()` and walks the entire tree to completion before scanning
anything, so first-result latency scales with how large the project is rather
than with how quickly a match exists. On this repository the two numbers are the
other way round — 177 ms to first, 607 ms to all — which is why it has never
shown up. Related to 0441, which is about what the results are for once they
arrive.

### 3. A tree that is walked costs four seconds of processor

Listing the root of the Platform is 5.4 ms; walking all of it is 4835 ms wall and
3979 ms of processor over 22,680 listings. The laziness is the whole design and
it is holding — 477 rows at rest after ninety seconds of a project importing
itself. What the pair of numbers gives is a price for anything that ever walks
the lot: "expand all" is a four-second main-thread stall on this corpus, and the
pre-`loadedNode(for:)` watcher, which pulled directories into the tree an event
at a time and never let them go, was heading for that figure and past it.

### 4. Every launch left a language-server container running

Found while clearing up, and it changes two things above.

jdtls did not run on this machine at all. It ran in an Apple `container` VM from
`pharndt/abydos-jdtls:dev` — 0401's work, and the catalogue picked it over the
`/opt/homebrew/bin/jdtls` that is also installed. Six app launches started six
containers, each a guest with four CPUs and a gigabyte, and **every one of them
was still running afterwards**, its starting process long dead:

    abydos-lsp-jdtls-42461-32   abydos-lsp-jdtls-58460-32   abydos-lsp-jdtls-84181-32
    abydos-lsp-jdtls-48322-32   abydos-lsp-jdtls-73032-32   abydos-lsp-gopls-48322-4

`AppDelegate.sweepContainersLeftBehind` clears these — but only when the *next*
app starts, so between two runs they simply accumulate. This is 0427's subject
seen from a new angle: not a server that outlives its project, but one that
outlives the whole application, holding a virtual machine.

Two consequences for the numbers above, both in the direction of honesty:

- **The jdtls figures are a VM's.** "1.8–2.0 GB resident, 46 seconds of
  processor" is the container-runtime process on this side, not a JVM's heap.
  It is the right number for "what does asking for Java cost this machine", and
  the wrong one for "how big is jdtls's index".
- **The later runs were taken on a machine carrying the earlier runs' orphans.**
  The Platform run had three or four of these VMs already up. That does not
  touch the processor time of our own process, which is per-process and is where
  finding 1 lives, but it inflates the *wall clock* and the load averages in the
  window table. The Sirius run, taken first, is the cleaner of the two — and it
  shows the same 8.4 cores.

### 5. Nothing colours a multi-repository project

Not slow — absent. The Platform aggregate is nine sibling clones under one
directory, which is exactly the shape a Tycho product with several repositories
has, and `Project.git` finds nothing at the root. No colour, no change count, no
changes pane. Worth an item of its own.

### And what turned out to be fine

- **The language-server scan.** 27 ms and 94 listings at open on 1022 bundles.
  Real, and on the main queue, but nowhere near the top of the list. 0437's
  one-walk-per-project cut what would otherwise have been roughly ten times
  that; at this scale that saving is a few hundred milliseconds off every
  project open, which is worth having and is not what hurts.
- **`loadedNode(for:)`.** One directory re-read on the Platform and none on
  Sirius, across 481 watcher batches naming 1,984 paths. The fix landed today
  and this is the case it exists for; at this scale it is holding perfectly.
- **`git status`.** 666 ms cold and 314 ms warm on `eclipse.platform.ui`, against
  24 ms here. Large, and it runs on every filesystem event — but it is coalesced,
  it is a child process rather than our main thread, and the reaped-children
  total of 5.9 seconds over ninety seconds of a project importing itself says it
  is not where the time goes.
- **Time to a window.** 1367 ms on 1022 bundles against 550 ms on this
  repository. Two and a half times the small project for a project two hundred
  times the size is the lazy tree working.

## What was not reached

- **Time until Java answers**, which the item expected to dominate. It does not
  appear above and the reason is finding 1: while the app is burning eight cores
  the machine is not in a state where "how long until go-to-definition comes
  back" is a question about jdtls. Asking it honestly means either fixing the
  scan first or measuring on a build with that path disabled, and both are
  changes this item said it would not make. What *is* recorded is jdtls's own
  cost beside ours, which was the other half of the question: on Sirius it held
  **1.8–2.0 GB** resident and spent **46 seconds** of processor time in the first
  seventy — real, and an order of magnitude less than the 729 seconds we spent
  over the same span, and see finding 4 for what that figure actually measures.
  The honest headline is the opposite of the one expected: at this scale, so
  far, **the indexer is not the expensive thing in the room.** That is a claim
  about ninety seconds, not about an afternoon, and the thing it does *not* say
  is that jdtls has finished — only that while it was working, we were working
  eight times harder.
- **Memory after an hour.** Readings are at 5, 30 and 90 seconds. Ours was still
  climbing at ninety on both corpora, so an hour's figure would be worth having
  and is a longer run than this item had time for.
- **Filesystem events *per build*.** What is measured is events during a project
  import, which is what actually happened when the corpora were opened and is
  arguably the harder case. Nothing here ran `mvn` over 1022 bundles.
- **Papyrus.** Sirius was used for the inner loop instead. Both are RCP and
  Tycho and either would do; Sirius is one repository where Papyrus is four, and
  a corpus whose job is to be quick to measure should not need its own
  aggregator.

## Ruled out

- **`FileNode.read` sorting every directory**, which the item named as a
  suspect. It is not one at this scale: listing the root of the Platform is
  5.4 ms including the sort, and even walking all 22,680 directories is 4 s of
  processor for 94,000 nodes. Sorting is not what makes any of these numbers.
- **`git status` as the thing that burns the machine.** Ruled out by measurement
  rather than by reading: the Platform aggregate has no repository at its root,
  runs no `git status` at all, and burns *exactly the same* eight cores.
- **The filesystem watcher re-reading expanded directories.** One directory
  re-read in 228 batches. Whatever this was before today, it is not this now.
- **`--stop-after` as a way to end a driven run.** It stops a run configuration,
  and this harness has none, so the app sat there until something killed it and
  its report was never flushed. `--close-window` terminates the app the way a
  person does.
- **`test -d .git` as a way to ask whether something is a repository.** In a
  worktree `.git` is a file pointing at the real one, and the first harness run
  announced "no repository at this root" about a checkout that plainly is one.
- **Assuming jdtls would be the local one.** `/opt/homebrew/bin/jdtls` is
  installed on this machine and was never used: the catalogue preferred the
  container image, so every Java number here is about a VM. Worth knowing before
  reading any of them, and it took clearing up after the runs to notice.
- **Asking `ps` for any process named jdtls.** It found the one belonging to the
  Abydos already running out of `/Applications` and reported somebody else's
  indexer as the cost of opening this corpus. The harness now looks only at its
  own app's children. A number that is mostly somebody else's is worth having as
  long as it says so; one that is entirely somebody else's while claiming to be
  ours is worse than none.
- **`sample`, `atos` and anything else that symbolicates this app, as built.**
  Two profiles were read and discarded before this was noticed:
  `Scripts/bundle.sh` pins a fixed build UUID — `Scripts/pin-uuid.py`, so macOS
  keeps the app's granted permissions across rebuilds — and the symbol server
  then answers for whichever binary first claimed that UUID. Both profiles came
  back naming a completely different application's SwiftUI views, plausibly
  enough to be believed. `make build PIN_UUID=0` produces something a profiler
  can read, and that is how finding 1 was actually identified. Anybody profiling
  this app needs to know it; it belongs in an item of its own.
- **Letting this suite run as part of `make test`.** It is a `…LiveTests` and
  the convention is that those run whenever what they need is present. This one
  cannot, because its listings are visible to another suite's claim (above), so
  it is behind `SCALE=1` and `make scale`. Suits it anyway: a dozen seconds over
  763 MB of somebody else's source, asserting nothing.
- **`#require(someBool)` as a way to skip.** It fails rather than skipping, so
  four scale tests went red on every machine without the corpus. Every other
  live test here uses `guard … else { return }`, and now so does this one.
- **Counting bundles with `find -name pom.xml`.** Says 104 where there are 1022,
  because Tycho builds most of them pom-less.
- **`xargs -0 wc -l | tail -1` for a corpus-wide line count.** Forty thousand
  paths do not fit in one `xargs`, so `wc` runs several times and prints a total
  each; the last of them said 108,594 lines for a corpus of 7.5 million. It was
  written into this item and believed for about ten minutes.

---

Its number is where it sits in the queue, not what it is worth doing next.
