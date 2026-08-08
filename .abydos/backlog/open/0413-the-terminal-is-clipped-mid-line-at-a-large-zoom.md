# 413. The terminal is clipped mid-line at a large zoom

At 2× the terminal below the editor shows a part-row against the top of its
viewport: a line cut through the middle rather than a row that is simply not
shown. The rest of 409 is fixed — names truncate at the pane's edge, the icons
are the right weight, and the blue dashes turned out to be the markdown icon —
but this was in that entry's opening paragraph and not in what it decided, so
it comes out as its own item rather than quietly disappearing with the rest.

**Where it probably is.** The terminal's height is whatever the split gives it,
and the grid is `floor(height / rowHeight)` rows — so any remainder is a strip
of a row, and at 1× that strip is small enough that nobody minds. Scaling
multiplies the row height and rounds it, so the remainder scales with it: a
four-point gap at 1× is a partial row eight points tall at 2×, which is enough
of a line to read as broken.

Three answers, and choosing between them is most of the work:

- **Round the terminal's height down to a whole number of rows**, and let the
  split's divider sit where that leaves it. Correct-looking always, at the cost
  of the divider not landing exactly where it was dragged.
- **Pad the remainder with background**, so the strip is empty rather than half
  a line. Keeps the divider honest and is a small change.
- **Clip the top row rather than the bottom one**, which is what a terminal
  scrolled to the end usually wants — the newest line whole, the oldest cut.

The second is the smallest and the third is the most like what a terminal is
for. Worth photographing at `--zoom 2.0` before deciding, since which end is
cut is not stated above from evidence.

---

Its number is where it sits in the queue, not what it is worth doing next.
