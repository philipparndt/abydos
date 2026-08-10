# 446. Opening a Tycho project spins the app at eight cores, for ever

Found by 0428 while taking the first numbers at five hundred bundles, and it was
on nobody's suspect list. It is the largest thing between this app and the
Java/RCP product it is meant to be used on.

**Open Eclipse Platform and the app burns eight to nine cores and does not
stop.** Not for a minute while something indexes — indefinitely, for as long as
anything is writing into the project.

Measured, processor time by ninety seconds after opening:

| project | our cpu at 90 s |
|---|---|
| Eclipse Platform, 1022 bundles | **758,637 ms** |
| Sirius, 106 bundles | **728,722 ms** |
| this repository | 2,288 ms |

Sirius is a fifteenth of the size and costs the same, which is the shape of the
fault: it is not proportional to the project, it is proportional to *how much is
being written* while the project is open.

## What it is

`onFilesChanged` reaches `refreshRunConfigurations`, which walks the whole
project looking for Java `main` methods. It is thrown at a concurrent queue with
**no coalescing at all**, once per filesystem event.

While that happens, jdtls is importing the reactor and writing Eclipse metadata
into all 1022 bundles, which is what generates the events. 0428 counted **228
batches**, so 228 concurrent walks of 45,772 files, all of them looking for the
same thing and all but the last one already stale by the time it finishes.

## Ruled out, by measurement rather than by reading

- **It is not `git status`.** The obvious suspect, and wrong: the Platform
  aggregate has no repository at its root, so the app runs no `git status` there
  at all — and it burns identically. That is why the number is worth more than
  the reading.
- **It is not the navigator watcher.** `loadedNode(for:)` landed the same day and
  0428 confirms it holds at this scale: one directory re-read across 481 batches.
- **It is not the language-server scan.** 27 ms over 94 listings after 0437's
  first round.

## Worth knowing before starting

`Scripts/pin-uuid.py` pins a fixed build UUID, and `sample` then symbolicates
against whichever binary first claimed it — two profiles came back naming another
application's SwiftUI views, plausibly enough to be believed. `make build
PIN_UUID=0` is what actually found this. That is 0447 and it will bite whoever
profiles this.

## Reproducing it

Two things had to be put right before a single number here meant anything, and
both are worth the paragraph because both produced numbers that looked fine.

**The corpus was no longer in the state the fault needs.** 0428's own runs left
their Eclipse metadata in it — 389 modified and deleted files in Sirius, 38 in
`eclipse.jdt.core` — and a jdtls workspace under
`~/Library/Caches/ideai/jdtls`. Open it again and the import writes nothing,
because everything it would write is already there: **3 watcher batches and 18.8
seconds of processor by ninety**, against the 728 seconds 0428 recorded. Which
is the finding restated rather than a contradiction of it — the cost is
proportional to how much is being *written*, and on a second open nothing is.
Every measurement below therefore starts by putting the corpus back:

    git -C <corpus> checkout -- . && git -C <corpus> clean -xdfq
    rm -rf ~/Library/Caches/ideai/jdtls/<project>-*

**The harness could not launch the app without a `FILE`.** `Scripts/scale.sh`
expands `"${FILE_ARGS[@]}"` and macOS's bash 3.2, under `set -u`, calls an empty
array unbound. Every run 0428 took passed a file to type into; the first run
without one launched nothing and then printed ninety seconds of "not running"
beside a falling load average. Fixed here.

## Is the walk needed at all

**No, and that is the fix rather than the coalescing.**

Coalescing makes the fault survivable: one walk of 45,772 files runs
continuously instead of two hundred at once, so the app burns about one core
for the whole import rather than eight or nine. That is a great deal better and
it is still a core spent answering a question whose answer did not change.

The walk exists to find Java `main` methods and build files. A `main` method
appears when a *source file* is written. jdtls importing a Tycho reactor writes
`.project`, `.classpath` and `.settings/*.prefs` — none of which can add one.
The information needed to tell the two apart was already in hand and was being
thrown away: FSEvents names the paths, and `FileSystemWatcher` reduced every
batch to the set of parent directories, at which granularity "a language server
wrote metadata into this bundle" and "somebody added a `main` method to a class
in this bundle" are the same event.

So the watcher now carries the names beside the directories, and
`RunConfigurationDiscovery.deservesRescan(after:)` decides. A batch that names
only files no finder in `discover(in:)` reads costs a set membership test per
path and nothing else.

Three things it is careful about, each of which would otherwise be a play button
that never appears:

- A batch FSEvents refused to describe file by file — `MustScanSubDirs`, which
  is how a checkout or a build arrives — says so, and is always scanned.
- Anything under `.idea` or `.vscode` counts, because IDEA rewrites its
  workspace under several names.
- The list of names lives next to the finders that read them, so adding a build
  system without adding its manifest to the list is at least in the same file.

Both were done. The filter removes the fault; the coalescing bounds what is left
when the filter honestly says yes — a `git checkout` across a large repository
names thousands of Java files across a handful of batches, and each of those
really is a reason to scan.

## Steps

- [x] Reproduce with `Scripts/scale.sh` against the corpus, and confirm the
      per-process processor time rather than the load average
- [x] Coalesce: one walk outstanding at a time, with at most one queued, the way
      `git status` already is
- [x] Ask whether the walk is needed at all on an event — a `main` method appears
      when a *file* changes, not when metadata is written beside it
      — **answered: no, and both were done.** See "Is the walk needed at all"
      above. The filter is what removes the fault; the coalescing is what keeps
      it removed when the filter legitimately says yes a thousand times at once.
- [x] Measure again on both corpora and put the before and after in this entry
- [x] Write down here what was ruled out on the way
- [x] `spec/<capability>.md` says what the project now does
- [x] A test that fails on the old answer: the metadata a language server writes
      is not worth a scan, and a source file among it still is

---

## The numbers

**Conditions, and they are not good ones.** A ten-core machine that was never
quiet: another agent was working 0437 throughout, the user's own Safari,
OrbStack and an installed Abydos are the floor, and one measurement had to wait
out somebody else's `swift test` at 645% of a core. Every reading below carries
its own load average for that reason, and **the number to read is the processor
time of our own process**, which is per-process and is the one thing on this
page that the rest of the machine cannot inflate. Wall-clock figures are marked
as such.

Three of the four runs were started at a one-minute load average between 13 and
15. The exception is the Sirius before-run, which started at 24.8 because the
machine had not finished settling — so of the four, the one taken on the busiest
machine is a *before*, and a process that gets fewer cores accumulates less
processor time. That understates the fault rather than the fix, which is the
direction to be wrong in.

Release `.app`, built `PIN_UUID=0` so a profiler could read it (0447), driven by
`Scripts/scale.sh` with `AT=5,30,90`. The corpus was put back to pristine and
the jdtls workspace deleted before each of the four runs, so each is a first
open of a project nothing has imported yet.

### Eclipse Platform, 1022 bundles, 45,772 Java files

| at | before | after |
|---|---|---|
| processor, ours, 5 s | 12,948 ms | 5,043 ms |
| processor, ours, 30 s | 155,062 ms | 7,089 ms |
| **processor, ours, 90 s** | **667,907 ms** | **10,779 ms** |
| memory, ours, 90 s | 312.6 MB | 86.9 MB |
| load average at 90 s | 157.6 | 11.5 |
| watcher batches by 90 s | 211 | 184 |
| whole-project scans | 211 | **2** |

### Sirius, 106 bundles, 8,307 Java files

| at | before | after |
|---|---|---|
| processor, ours, 5 s | 10,710 ms | 5,265 ms |
| processor, ours, 30 s | 126,022 ms | 9,301 ms |
| **processor, ours, 90 s** | **417,204 ms** | **12,726 ms** |
| memory, ours, 90 s | 164.0 MB | 126.8 MB |
| load average at 90 s | 159.1 | 30.6 |
| watcher batches by 90 s | 149 | 456 |
| whole-project scans | 149 | **2** |

**62× on the Platform and 33× on Sirius**, in processor time by ninety seconds.
Two scans in each after-run, and both of them are the ones at project open that
have always been there; not one of the 184 and 456 watcher batches earned a
third. The app's own report says so directly — `--report-open` now prints
`run configurations   456 asked, 456 skipped, 5 coalesced, 2 walked` beside the
watcher's batches, and before this change those first and last numbers were the
same by construction, because nothing between them existed.

Three things in those tables are worth more than the headline:

**The Sirius after-run saw three times as many watcher batches as the
before-run** — 456 against 149. That is not noise and it is not a worse case
handled: it is jdtls getting three times as far in the same ninety seconds
because the eight cores it was competing with are no longer being spent. The
right reading of the pair is not "the same work for a thirty-third of the cost"
but "three times the language server's work done, for a thirty-third of the
cost". The children's processor time says the same thing from the other side:
12,519 ms before, 29,904 ms after.

**The load average follows.** 157.6 down to 11.5 on the Platform. 0428 said that
where a load average above 10 appears it is the app under measurement causing
it, and that is exactly what stopped.

**Memory too**, which was not the complaint but is the same fault seen sideways:
312.6 MB down to 86.9 MB at ninety seconds on the Platform. Two hundred
concurrent walks each hold their enumerator, their strings and their partial
results, and `mainClasses` reads every file it visits into a `String`.

### Read in the app rather than in a table

Two driver runs on a five-file Maven project, to check that the thing the walk
existed for still happens:

- 24 batches of nothing but `.project` and `.settings/org.eclipse.jdt.core.prefs`
  rewritten: `24 asked, 24 skipped, 0 coalesced, 2 walked`. Not one scan.
- `.project` and `.settings` written first, then a class with a `main` method,
  all after the window was up: `--run-configs` printed
  `Java: run App → mvn compile exec:java -Dexec.mainClass=demo.App`. The play
  button still arrives for a file written while the project is open, which is
  the whole reason the walk was on this path.

## Ruled out, and what surprised me

- **Coalescing on its own.** It was the item's first step and it is not the
  answer, only half of it. One walk at a time still means one walk running
  continuously for the length of the import — a core spent, indefinitely,
  answering a question whose answer did not change. Kept, because the filter is
  not a guarantee; not relied on.
- **Filtering on the changed *directories*.** The obvious cheap version, and it
  cannot work: a bundle's `.classpath` and a bundle's Java sources live under
  the same directory, so at that granularity "a language server wrote metadata"
  and "somebody wrote code" are one event. The names had to be carried, and
  FSEvents had them all along — `FileSystemWatcher` was reducing every batch to
  parent directories and throwing the rest away.
- **Making the walk itself cheaper.** Tempting — `mainClasses` reads every Java
  file in the project into a `String` and splits it on newlines — and it is the
  wrong end. A walk that is twice as fast, run 211 times for no reason, is 334
  seconds of processor instead of 668. Untouched, deliberately: it is now run
  twice per project open, where four seconds is a price the app can pay.
- **`limit: 40` saving anything.** `mainClasses` stops after 40 entry points, so
  a project full of `main` methods is cheap. Eclipse Platform has almost none in
  45,772 files, so the limit is never reached and every file is read. The guard
  protects exactly the projects that did not need protecting.
- **Blaming jdtls for the load.** It is what generates the events, and this
  fault is ours end to end: 668 seconds of our processor time against 1.4
  seconds of our children's over the same ninety on the Platform. After the fix
  the children cost *more* than they did before, which is the machine finally
  being available to them.
- **Trusting a re-open of the corpus to reproduce it.** 0428's runs left their
  Eclipse metadata in the corpus and a jdtls workspace in `~/Library/Caches`, so
  the second open imports nothing, writes nothing, and costs 18.8 seconds. That
  first run looked like the fault having been fixed by somebody else. Every
  measurement here therefore resets the corpus and deletes the workspace first.
- **`Scripts/scale.sh` without a `FILE`.** bash 3.2 under `set -u` treats an
  empty array expansion as unbound, so the app was never launched and the
  harness printed ninety seconds of readings about a process that did not exist.
  Fixed.
- **The first two runs of this item entirely.** This shell had a stale
  `TMUX_TMPDIR` in it, left by an agent killed the day before, pointing at a
  path deep enough that the socket tmux derived from it was about 140 characters
  against macOS's ~104 limit. The app inherits the variable, hands it to the
  tmux it starts for its terminal, and the terminal comes up
  `[process exited with status 1]`. Both early runs were of an app whose
  terminal never started, and neither created a tmux session on the default
  server, which is how it was caught. Every measurement in the tables above was
  taken with `env -u TMUX_TMPDIR` in front of the harness and was checked to
  have created its session. Nothing in the tables is from a run that hit it.
- **`sample` and `atos`, again.** Not repeated here — 0428 paid for that lesson
  and the profile it produced was enough. The build for these numbers was
  `make build PIN_UUID=0` regardless, because a profiler that names another
  application's SwiftUI views is worse than none. See 0447.

## What was not measured

- **A unit test of the coalescing.** The filter is tested — the metadata a
  language server writes is not worth a scan, a source file among a hundred
  metadata writes is, and a batch FSEvents would not name is always scanned. The
  one-at-a-time-with-one-queued part lives in `MainWindowController`, which has
  no test target at all, and it is claimed here only by the counter the app
  prints: `5 coalesced` on Sirius and `1 coalesced` on the Platform, both from
  the two scans at open overlapping. Nothing here proves it under a burst of
  thousands of genuine source writes; a `git checkout` of a large branch on the
  corpus would, and was not run.
- **Anything past ninety seconds.** Same horizon as 0428. Ours was still
  climbing at ninety before the change and flat after it, but "flat at ninety
  seconds" is not "flat after an hour".
- **Time until Java answers**, which is 0428's unreached step and the reason it
  gave was this fault. It is now worth asking, and it is that item's question
  rather than this one's.
- **A quiet machine.** There was not one to be had. The processor-time figures
  are per-process and stand; the wall-clock figures in `Scripts/scale.sh`'s own
  table were not used for any claim here.
