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

## Steps

- [ ] Reproduce with `Scripts/scale.sh` against the corpus, and confirm the
      per-process processor time rather than the load average
- [ ] Coalesce: one walk outstanding at a time, with at most one queued, the way
      `git status` already is
- [ ] Ask whether the walk is needed at all on an event — a `main` method appears
      when a *file* changes, not when metadata is written beside it
- [ ] Measure again on both corpora and put the before and after in this entry
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
