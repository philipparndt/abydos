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

## Decided, and done

**Round the terminal's height down to a whole number of rows**, and let the
divider sit where that leaves it. The trade taken knowingly: the divider does
not land exactly where it was dragged, and the terminal always looks like a
terminal.

`TerminalView.heightRemainder` reports what is left over, and the panel gives
it back from `splitViewDidResizeSubviews` — after the split has resized rather
than while it is being dragged, because a drag is not the only thing that
changes the height. The window, the zoom and the font all do, and only the
notification catches all four.

**Two things it cost, both worth writing down.** Moving the divider resizes the
subviews, which is the same notification again, and `setPosition` sends it
synchronously — so the first version ran inside itself and took the app out
with a stack overflow (`exit=139`) before the remainder ever reached zero.
Converging is not terminating. It is guarded by a flag now and does its work on
the next turn of the loop rather than inside the layout pass reporting to it.

The other was a false alarm worth remembering: the first screenshot of the
split came back as an empty window, which looked exactly like this change
collapsing both panes. It reproduces byte-for-byte without the change — same
md5 — so it belongs to that combination of harness flags and not to this. The
check took two minutes and would have cost an afternoon of reverting the wrong
thing.

The two that were not chosen, since the reasoning is still worth having: padding
the remainder with background keeps the divider honest and is a smaller change,
and clipping the top row rather than the bottom is what a terminal scrolled to
the end usually wants.

---

Its number is where it sits in the queue, not what it is worth doing next.
