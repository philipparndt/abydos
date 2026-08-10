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
      below. The filter is what removes the fault; the coalescing is what keeps
      it removed when the filter legitimately says yes a thousand times at once.
- [ ] Measure again on both corpora and put the before and after in this entry
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
