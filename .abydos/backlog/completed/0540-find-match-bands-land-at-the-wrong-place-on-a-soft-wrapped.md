# 540. Find match bands land at the wrong place on a soft-wrapped line

Found by the work on 0536, which did not fix it and said so:

> match bands are measured against the *whole* line even when soft wrap is on, so
> on a wrapped line they are painted at the wrong place on every row of it.
> `images/wrapped-line-defect.png` shows the current match landing on the word
> `word` with neither `publish` marked.

The screenshot is attached to 0536 in `completed/0536-…/images/`.

**Older than 0536, and more conspicuous because of it.** The arithmetic is the
same expressions 0536 moved from `drawSearchHighlights` into
`searchHighlights(docLine:rect:)` — moved, not touched — so this has been true as
long as find-in-file and soft wrap have coexisted. What changed is that the
current match is no longer painted over by the selection, so a band in the wrong
place is now a bright band in the wrong place.

## Where it comes from

`searchHighlights` builds one `CTLine` for the whole document line and asks it
for the x of each match:

    let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)

With soft wrap on, a document line is drawn as several visual rows, each holding
a slice of it, and `CodeView` already knows how to do that — `firstVisualRow`,
`wrapSegmentForOffset` and the wrap layout `updateFrameSize()` builds are what
`point(forUTF16:)` uses to place the caret correctly on a wrapped line. The
highlight path predates that and asks the unwrapped line, so every offset past
the first row's end is measured along a row that is not the one being painted.

That the caret lands correctly and the band does not is the shape of the fault:
two answers to "where is this offset on screen", one of which knows about wrap.

## Worth deciding

- **Whether to reuse `point(forUTF16:)` or teach the highlight path the wrap
  layout.** The caret's answer is already right and already handles folding; a
  second implementation that agrees today is how the two come to disagree later.
  Against that, `point(forUTF16:)` answers for one offset and a band needs a pair
  per visual row, so the reuse may want a range-shaped sibling rather than a call
  per end. 0533 added `RevealScroll` with exactly that range/point distinction in
  mind and may be worth reading first.
- **A match that spans a wrap boundary** is not one rectangle. It is one band per
  visual row it touches, the first running to the end of its row and the last
  starting at the row's beginning. The current code cannot express that at all,
  and it is the case most likely to be got half right.
- **Whether folding has the same fault.** A collapsed region changes which
  document line a visual row shows, and the highlight path takes `docLine` from
  the caller — worth checking rather than assuming, since it is the same class of
  bug and the same screenshot would not show it.
- **What to assert.** The visible fault is pixels, but the arithmetic is testable
  without a window if the offset-to-x step is pulled out — which is what 0536 did
  for the *order* and is why that part now has tests.

## Steps

- [ ] A match on a soft-wrapped line is drawn on the characters it matches, on
      whichever visual row they are on
- [ ] A match spanning a wrap boundary is drawn on both rows, each part on the
      right characters
- [ ] The caret and the band agree about where an offset is — one answer, or two
      that a test holds together
- [ ] Folding checked, and either fixed with this or named here as unaffected
- [ ] Screenshots on a wrapped line with several matches, before and after
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way

## Done as an OpenSpec change

The work is in `openspec/changes/archive/2026-08-17-find-bands-follow-soft-wrap/`, and that change's `tasks.md` is
the record of what was done. The checklist above is left as it was written: the
work did not go through it, so nothing here was ticked from memory.
