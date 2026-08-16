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

## Steps

- [ ] Reproduce it from outside the app, with a query short enough to hurt, and
      say how long it takes before the fix
- [ ] Streaming results does not rebuild what has already been built
- [ ] The list is bounded, by whatever was decided, and says so when it is
- [ ] The window keeps answering while a broad search runs — measured, not
      judged by eye
- [ ] Watched: type two characters into a project of real size and keep typing
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` says what the project now does
