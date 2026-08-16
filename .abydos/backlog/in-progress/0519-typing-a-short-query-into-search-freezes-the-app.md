# 519. Typing a short query into search freezes the app

> I had to force quit (the search view was frozen) … The freeze occurred after I
> typed to the view and it tried to live filter with only a few characters

Two or three characters into the search field and the window stops answering.
Not slow — force-quit frozen.

## Why

`SearchPane.runSearch` accumulates and then re-sets **the whole list on every
batch**:

    onResults: { [weak self] batch in
        self.results.append(contentsOf: batch)
        self.list.setResults(self.results)
    }

`setResults` calls `rebuildRows`, which walks every result and every match in
the accumulated array, asking `SearchChecklist.marks(for:)` and
`checklist.isDone(_:for:)` per match, and then reloads the table. On the main
thread.

A two-character query over a real project matches tens of thousands of times
and arrives in many batches. Batch *n* rebuilds everything found so far, so the
work is quadratic in the number of results — and every bit of it is on the
thread that draws the window. The debounce above it (0.25 s, `scheduleSearch`)
delays the start and does nothing about the flood once it begins.

**Nothing bounds the result count.** A one-character query is a request to
build a row for a large fraction of the lines in the project.

## Worth deciding

- **Where the bound goes.** Capping results, coalescing the batches into one
  redraw every so often, and rebuilding only the rows that arrived are three
  different fixes and they are not exclusive. The one that must be there is the
  last: appending should not be O(everything so far).
- **What a capped list says.** Silently showing the first N is the failure this
  program keeps refusing elsewhere — a count that says `2000+ in 340 files,
  showing the first 2000` is honest and a truncated list that looks complete is
  not.
- **Whether a very short query searches at all.** A minimum length is the
  cheapest possible answer and it is a refusal, which is worth weighing against
  the two above rather than reaching for first: somebody searching for `if` in
  one small project has a reasonable request.
- **The marks.** `rebuildRows` recomputes every mark on every rebuild. Those are
  keyed on the question and the matched text, so they are stable while results
  stream in — caching them per result is available if the profile says so.

## What it measured, before the fix

Debug build, this repository open (~1500 files under the walk), the app driven
with `--search` and `--search-steps`. The instrument is the one already in the
program: `StallWatch` pings the main queue ten times a second from a thread of
its own and writes every late ping to `~/Library/Logs/Abydos/stalls.log` with
the pid. A stall in that log *is* the window not answering.

| query | matches found | worst single stall | main thread blocked, in total |
|---|---|---|---|
| `in` | 88 578 in 500 files | 577 ms | 1.31 s over 4 stalls |
| `e` | 440 854 in 500 files | **7 032 ms** | **9.38 s over 4 stalls** |
| `e`, second run | 440 854 in 500 files | **4 292 ms** | **5.94 s over 4 stalls** |

Four stalls and not forty, because the batches arrive faster than the main
thread eats them: the watchdog's own ping queues *behind* twenty pending
rebuilds and comes back once, seven seconds late. That is the shape of the
force quit — not a stutter per batch, one dead window.

Every one of those lines says `idle`, which is `StallWatch` saying nobody had
named the work. Seven seconds at `cpu 100%` and no name is exactly the case its
own comment says the field exists to find.

### What the stack said

`sample` over the frozen process, 12 s at 1 ms:

    6866 samples on the main thread
    └ 5075  ResultChecklist.setResults(_:)            ← 74% of the whole sample
      └ 2790  rebuildRows, line 220  SearchChecklist.marks(for:)
        557  rebuildRows, line 221  checklist.isDone
        264  rebuildRows, line 222  flags.filter
        762  rebuildRows, line 218  the rows array growing
        234 + 107 + …                rows.append
           7  -[NSTableView reloadData]

So the item's mechanism is confirmed and one guess in it is wrong: **the table
is not the cost.** `reloadData` is 7 samples in 6866 — a tenth of a percent.
The whole of it is recomputing the marks, the done flags and the row array for
everything found so far, once per batch. `marks(for:)` alone is a `trimmingCharacters`
and a dictionary of `String` keys per match, redone 25 times over.

## Estimate

2026-08-16 21:40 — about three hours left

## Steps

- [x] Reproduce it from outside the app, with a query short enough to hurt, and
      say how long it takes before the fix
- [x] Streaming results does not rebuild what has already been built
- [x] The list is bounded, by whatever was decided, and says so when it is
- [x] The window keeps answering while a broad search runs — measured, not
      judged by eye
- [ ] Watched: type two characters into a project of real size and keep typing
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` says what the project now does
