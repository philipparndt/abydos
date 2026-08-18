## Why

Find-in-file match bands are measured against the **whole** document line even when
soft wrap is on, so on a wrapped line they are painted at the wrong place on every
row of it. `images/wrapped-line-defect.png`, attached to completed item 0536, shows
the current match landing on the word `word` with neither `publish` marked.

`searchHighlights` builds one `CTLine` for the whole document line and asks it for
the x of each match:

    let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)

With soft wrap on, a document line is drawn as several visual rows, each holding a
slice of it. `CodeView` already knows how to do that — `firstVisualRow`,
`wrapSegmentForOffset` and the wrap layout `updateFrameSize()` builds are what
`point(forUTF16:)` uses to place the caret correctly. The highlight path predates
that and asks the unwrapped line, so every offset past the first row's end is
measured along a row that is not the one being painted.

**That the caret lands correctly and the band does not is the shape of the fault:**
two answers to "where is this offset on screen", one of which knows about wrap.

**Older than 0536 and more conspicuous because of it.** The arithmetic is the same
expressions 0536 moved from `drawSearchHighlights` into `searchHighlights(docLine:rect:)`
— moved, not touched — so this has been true as long as find-in-file and soft wrap
have coexisted. What changed is that the current match is no longer painted over by
the selection, so a band in the wrong place is now a bright band in the wrong place.

From `.abydos/backlog/ready/0540-find-match-bands-land-at-the-wrong-place-on-a-soft-wrapped.md`.

## What Changes

- A match on a soft-wrapped line is drawn on the characters it matches, on whichever
  visual row they are on.
- A match spanning a wrap boundary is drawn as **one band per visual row it touches**
  — the first running to the end of its row, the last starting at the row's
  beginning. The current code cannot express that at all, and it is the case most
  likely to be got half right.
- The caret and the band agree about where an offset is: one answer, or two that a
  test holds together.
- Folding is checked. A collapsed region changes which document line a visual row
  shows, and `searchHighlights` takes `docLine` from the caller — the same class of
  bug, which the screenshot would not show.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `editor`: three requirements added beside "The current find match is the loudest
  thing on the page" and "The find highlights are the scheme's colours". Those two
  settle *which* band is loudest and *what colour* it is, and neither says a word
  about **where** it is painted — which is exactly how this survived. Nothing in them
  changes.

## Impact

- `CodeView.searchHighlights(docLine:rect:)` and `drawSearchHighlights`.
- The wrap layout: `firstVisualRow`, `wrapSegmentForOffset`, `updateFrameSize()`.
- `point(forUTF16:)`, if the fix reuses it or grows a range-shaped sibling.
- `RevealScroll`, added by 0533 with exactly this range/point distinction in mind —
  worth reading first.
- `.abydos/backlog/spec/search.md`.
