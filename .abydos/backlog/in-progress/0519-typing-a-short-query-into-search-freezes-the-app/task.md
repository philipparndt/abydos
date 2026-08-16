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

## What it measured, after the fix

Same build, same repository, the same instrument. `--search e` and then the
query changed three times while the walk was running, which is the "kept
typing" the report describes:

    SEARCH status: the first 20018 in  27 files · more not shown
    SEARCH status: the first 20019 in 225 files · more not shown
    SEARCH status: the first  4268 in 500 files · more not shown
    SEARCH status: the first 20006 in 171 files · more not shown

    stalls logged for that pid: none at all

Not one late ping, against 7.0 s and 4.3 s before. The third line is the
500-file bound rather than the match bound, and it is worth having in the
record: that cap has been there all along, and until now the pane printed
`4268 in 500 files` and looked complete.

An ordinary search is unchanged and says nothing about caps —
`rebuildRows` over this repository still reads `10 in 4 files`.

## The four decisions

**Where the bound goes.** All three of the fixes this item offered are not
needed; two are. *Appending only what arrived* is the one that had to exist and
it is `ResultRows.append`, which is O(the batch). *A cap* is the second, and it
is on the number of matches — `ProjectSearch.maximumMatches`, 20 000 — because
that is the number the row list is linear in and the only bound that existed
counted files. It stops the walk rather than the display: past it the remaining
files are not read, decoded or searched.

*Coalescing the batches into one redraw* is the one not done, and it is ruled
out by measurement rather than by taste: `sample` put `-[NSTableView reloadData]`
at **7 samples in 6866** while the window was frozen. Coalescing would have
bought a tenth of a percent and cost a timer, a pending flag and a rule about
what happens to a coalesced redraw when the search is superseded. With the cap
in place the row count is bounded anyway, so the reload is bounded with it.

**What a capped list says.** `the first 20018 in 27 files · more not shown`.
"the first" goes in front of the count, where it cannot be missed, rather than
after it. The interesting part is that this had to be built as far down as
`ProjectSearch`: `onFinished` reported `completed: true` whether the tree had
been walked or the 500-file limit had been hit, so the pane had no way of
knowing. `SearchOutcome.capped` is what carries it out, and the 500-file cap —
which has been silently truncating since long before this item — now says so
too.

**Whether a very short query searches at all.** No minimum length. It is the
cheapest fix and it is a refusal, and a refusal has to be worth what it buys:
here it buys nothing the cap does not already buy, and it costs the person
searching a small project for `if` — a reasonable question with a small answer,
which the fixed code answers in 1.1 ms. A minimum length would also be wrong in
the direction that is hardest to notice: it fails on the *query*, when the
thing that hurts is the *number of matches*, and those are only loosely
related. `re` in a Rust project and `re` in a repository of prose are the same
two characters and four orders of magnitude apart.

**The marks.** The profile says they are the whole cost — 2790 of the 5075
samples inside `setResults` were `SearchChecklist.marks(for:)`, with `isDone`
and the flags array behind them. But the answer is not a cache. They are
computed *once per file*, when the file arrives, and kept beside the results in
`ResultRows.marksByFile`; computing once is strictly better than memoising, and
a cache would have needed an invalidation rule for a thing that never goes
stale. The benefit shows up twice over: a rebuild for a reason that is not new
results — a row ticked, ⌘Z, a folded file, the hide-done toggle — is now a set
lookup per match rather than a `trimmingCharacters` and a `String`-keyed
dictionary per match.

## Ruled out, and what surprised us

- **The table is not the cost.** The item's account named `reloadData` as part
  of it and it is not: 7 samples in 6866. Everything was the arithmetic before
  the table was told anything. Worth knowing, because the obvious fix for a
  frozen table view — `insertRows(at:)` instead of `reloadData()`, batched
  updates, a diff — would have been most of a day and bought a tenth of a
  percent.
- **The 0.25 s debounce is not part of this.** It was left alone. It delays the
  start of a search and does nothing about the flood once it begins, which the
  item said and which the measurements confirm: the stalls all land two to
  three seconds after launch, well past the debounce.
- **`SearchChecklist.marks(for:)` was not the thing to make faster.** Its own
  comment anticipates this exact case — "a large search rebuilds these for
  every batch that streams in" — and it is already one pass and one dictionary
  per file. The caller was wrong, not the callee, and no line of it changed.
- **`StallWatch` is the instrument, and it is already in the program.** Nothing
  had to be written to measure the freeze. What it did say, four times, was
  `idle` — its own doc comment calls that the case worth finding, and the batch
  handler is now inside a `StallWatch.mark("search results")` so the next one
  arrives with a name on it.
- **`--search-steps` cannot observe the freeze**, and this is worth writing
  down for the next person: it recurses around `settle` on
  `DispatchQueue.main.asyncAfter`, so it is waiting on the very queue that is
  wedged. It reports the *result* faithfully and says nothing at all about how
  long the window was dead. The stall log, written from a thread of its own, is
  what can.
- **A `ResultRows` in `AbydosKit` rather than a fix inside the view.** The rows
  were in `ResultChecklist`, which is in the app target, where the suite cannot
  reach it — so the claim "appending does not rebuild" had nowhere to live. The
  model has no AppKit in it and the view kept the table, which is the line this
  repository already draws.
- **One suite fails and it is not this.** `CadovaExampleLiveTests` builds
  `~/dev/abydos-examples/cadova-models`, which is outside this repository and
  currently has `C ircle` in `Sources/coaster/main.swift` — somebody else's
  work in progress. It fails identically with `FILTER` on its own and nothing
  in this branch goes near it. `JavaLiveTests` flaked once in a full run and
  passed alone, which is the load.

## Estimate

2026-08-16 22:04 — about twenty minutes left

## Steps

- [x] Reproduce it from outside the app, with a query short enough to hurt, and
      say how long it takes before the fix
- [x] Streaming results does not rebuild what has already been built
- [x] The list is bounded, by whatever was decided, and says so when it is
- [x] The window keeps answering while a broad search runs — measured, not
      judged by eye
- [x] Watched: type two characters into a project of real size and keep typing
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [ ] `spec/search.md` says what the project now does
