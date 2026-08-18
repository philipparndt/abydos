## Context

There are two implementations of "where is this offset on screen" in `CodeView`.
One is `point(forUTF16:)`, which the caret uses: it knows the wrap layout and it
knows folding, and it is right. The other is inside `searchHighlights`, which builds
a `CTLine` for the whole document line and measures along it, and is right only when
the line fits on one row.

They have disagreed for as long as both have existed. The disagreement was invisible
while the selection painted over the current match; 0536 stopped that, correctly, and
the wrong band became bright.

## Goals / Non-Goals

**Goals:**

- A band covers the characters it matched, wherever they are drawn.
- A match crossing a wrap boundary is drawn on every row it touches.
- One answer to the offset-to-position question, or two that a test pins together.

**Non-Goals:**

- The order and colour of the bands. 0536 settled that — the current match is painted
  after the selection and the two colours are the scheme's — and it has tests.
- Changing the wrap layout itself. It is right; the highlight path simply does not
  ask it.

## Decisions

**Reuse the caret's answer, unless measurement forbids it.** The caret's answer is
already correct and already handles folding. A second implementation that agrees
today is how the two come to disagree later, which is precisely the history being
fixed. Against that: `point(forUTF16:)` answers for one offset, and a band needs a
pair per visual row — so the reuse likely wants a **range-shaped sibling** rather
than a call per end. `RevealScroll` (0533) was added with that distinction in mind
and is the first thing to read.

**A match is a list of rectangles, not a rectangle.** This is the part the current
code cannot express, so it is a change in shape rather than in arithmetic:
`searchHighlights` returns one rect per (match × visual row it touches). Getting
this half right — clamping to the first row, say — is the most likely bad outcome,
so the spanning case gets its own scenario and its own screenshot.

**Pull the offset-to-x step out so it can be asserted without a window.** The visible
fault is pixels, but the arithmetic is testable headlessly, and this is what 0536 did
for the *order* — which is why that part now has tests. `AbydosKit` holds no view
code, so whatever is extracted must be careful about which side of that line it
lands on; the wrap layout is already in the view.

**Cost matters: this runs per row, per draw.** A band is painted while somebody
scrolls a file with matches in it. Asking the wrap layout per match per row is the
straightforward implementation; if it is not cheap enough, say so in the comment
with the number rather than optimising quietly.

## Risks / Trade-offs

- **Folding has the same fault and is not visible in the screenshot** → Check it
  explicitly. `searchHighlights` takes `docLine` from the caller, so a collapsed
  region changing which document line a visual row shows is the same class of bug.
  Either fix it here or name it here as unaffected; do not leave it unexamined.
- **A range-shaped sibling of `point(forUTF16:)` is a second implementation after
  all** → Only if it is written separately. It should be built from the same layout
  lookups, and one test should assert that the caret's position and the band's edge
  agree for the same offset.
- **Extraction pushes view arithmetic into the wrong module** → The rule is that
  `AbydosKit` has no view code and the line has held. If the arithmetic cannot move,
  the test lives beside the view rather than the rule bending.

## Open Questions

- Does `RevealScroll` already have the range/point shape this needs, or does it only
  suggest it?
- Is folding affected, and is it the same fix or a separate one?
