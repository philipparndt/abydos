## Context

See proposal.md for why. What the code does today:

- `DiffView` is the document view of an `NSScrollView` with a vertical scroller
  only, pinned by its host to the clip view's leading, trailing and top edges —
  so its width *is* the visible width and there is nothing to scroll to
  sideways. Every host does this the same way (`PictureDiffHost.show` writes the
  constraints down once for all of them).
- Side by side, `drawPair` clips each half to its column and draws the text from
  `textOrigin(ofRow:in:)`; unified, `draw(rowAt:)` draws the marker at `textX`
  and the text after it, unclipped. `textOrigin` is also what `DiffTextRun`
  measures a pointer against, so it is the single number drawing and
  hit-testing agree on.
- The find bar's reveal (`DiffView+Search.selectCurrentMatch`) scrolls a row
  vertically and records sideways as a known gap.
- Measuring text costs: `DiffTextRun`'s own comment measured 5,000 row
  measurements at 104 ms. Anything per row per rebuild has to avoid that.

## Goals / Non-Goals

**Goals:**

- One horizontal offset per text column — `.only`, `.left`, `.right` — that
  every place which draws or hit-tests text adds in one spot.
- Scrollers that stay at the bottom of what is visible, in every host, without
  each host laying anything out.
- The link as the default, remembered.

**Non-Goals:**

- Wrapping long lines instead (`file-diff` follows ⌥⌘Z on the compare page).
  Wrapping changes row heights, and every piece of `DiffView` — drawing,
  selection, comments, search, the place-keeping on a switch — assumes one row
  is one `lineHeight`. Worth doing one day; not the smaller change, and not
  what was asked for.
- Autoscrolling sideways while a selection is dragged past the edge.
- The compare page's `FileCompareView`.
- Scrolling the line numbers with the text, as some tools do. The number is how
  a reader says which line they are on, and losing it to read the end of a line
  is the wrong trade.

## Decisions

### Offsets in `DiffView`, applied through `textOrigin`

`DiffView` holds `horizontalOffset[Column]`, clamped to
`0...max(0, widest[column] - visibleTextWidth[column])`. `textOrigin(ofRow:in:)`
subtracts the column's offset, so drawing and `DiffTextRun`'s hit-testing move
together — the selection requirement then holds without touching the selection
code. The number columns, gutter and row backgrounds do not use `textOrigin` and
so do not move.

Unified, the marker is drawn at `textX` and is not offset either: it says what
the line does, like the number beside it. The text is clipped to start after the
marker so that scrolled text does not run under the numbers — side by side
already clips each half this way.

Ruled out:

- **Making the document view wider and using `NSScrollView`'s own horizontal
  scroller.** One scroll offset for the whole view: the line numbers would
  scroll off with the text, and the two halves could not move separately, which
  is the request.
- **Two scroll views, one per half.** `FileCompareView`'s header already says
  why not: two views kept in step vertically are a frame late on every wheel
  event, and the halves are rows of one alignment.

### How wide a column is, cheaply

The scrollers need the widest line in each column. Measuring every row is the
104 ms the `DiffTextRun` comment warns about, so: at rebuild, one pass keeps
each column's twenty longest lines, then only those are measured with the code
font and the widest kept.

**Ranked by UTF-8 bytes. Changed while building it, twice.** The plan ranked by
UTF-16 length. A fixture line of 220 CJK characters showed why that fails: it
is 223 units against 317 for each of 25 ASCII lines, so it ranked below the top
twenty, yet it draws wider than all of them, and it was never measured. Weighing
each UTF-16 unit (tab as four, U+1100 and up as two) fixed the ranking but
walking every line cost 10–17 ms over 20,000 rows. Sorting wasn't the cost: a
running top twenty took the same time. UTF-8 byte count is known to a native
string without a walk, and a CJK character or an emoji is three or four bytes
for about two columns, so it ranks at least as wide as it draws. Measured after:
2.5–3.2 ms unified and 5–9.5 ms side by side over 20,000 rows, at load 0.1–0.3
per core; the measured width matched an exact all-lines measurement on the CJK
fixture.

The one way a line can rank narrower than it draws is tabs: a byte each, four
columns drawn. Measuring twenty rather than one is the margin for that.

### The scrollers live in the scroll view, beside the clip view

A `DiffSidewaysBar` view holds one `NSScroller` per column and, side by side,
the link button between them. `DiffView` installs it into its enclosing scroll
view in `viewDidMoveToSuperview` as an ordinary subview over the clip view,
along the bottom of the clip view's frame and pinned there by its autoresizing
mask, and takes it out again when it leaves (a picture diff swaps the
document view). **Changed while building it:** the plan was
`addFloatingSubview(_:for: .vertical)`, which this app had never used. A plain
subview of the scroll view isn't scrolled at all, so floating was never needed.
So every host
— changes pane, log, commit, stash, pull request — gets it without a line of its
own. It is hidden when nothing is wider than its column, and takes no space
then.

It overlays the last row rather than pushing it up: the document view's
intrinsic height gains the bar's height while the bar is shown, so the last row
can still be scrolled clear of it.

Ruled out:

- **A bar each host lays out below its scroll view.** Five hosts, five copies of
  the same constraints, and the next host forgets. The `DiffView` header already
  makes this argument about settings.
- **Drawing the scrollers into `DiffView` itself** at the bottom of
  `visibleRect`. It works, and is what the code view does for its own furniture,
  but it means hand-drawing a scroller's look and behaviour — the overlay style,
  the knob, paging clicks — which `NSScroller` already has right.

Seen working in the pull request page and the changes pane, which have
different layouts, without either of them laying the bar out.

**An `NSScroller` decides its orientation from the frame it is made with.** One
made at zero size and given a wide frame later drew itself as a vertical stub at
the end of its track; the bar makes them wide from the start.

### Wheel and swipe

`DiffView.scrollWheel(with:)` takes the horizontal component (`scrollingDeltaX`,
which is what a trackpad swipe and ⇧-wheel both produce) for itself, routed to
the column under the pointer — or both halves when linked — and passes the
vertical component to `super`, so vertical scrolling is untouched. A gesture
that is mostly vertical is left wholly to `super`: a slightly diagonal swipe
should read a page down, not drift sideways.

### The link

`Settings.diffHalvesScrollTogether`, default `true`. The button shows the SF
Symbol `link` in the accent colour when linked. When unlinked it shows the same
link, dimmed, with a slash drawn through it. **SF Symbols has no `link.slash`**:
I checked on this machine, and `link`, `link.circle`, `link.badge.plus`,
`lock` and `lock.open` exist, but no broken link. A slash is what "not" means
on every other slashed symbol, and it keeps the two states recognisably the
same control. `lock`/`lock.open` was ruled out: a lock says "can't be changed",
which is not what linking does.

A driven run can show "remembered across diffs" but not "across launches":
driven runs write preferences into an in-memory domain seeded from the real
one, deliberately, so nothing they write reaches disk. Across launches it
behaves like every other `Settings` key, and a unit test claims the default
and the write-back against `TestDefaults`.

The magnet in the request was considered: it says "these stick together", which
is right, but a magnet usually means snapping to a guide, and a chain link is
the symbol image editors already use for "these two values move together".

Linking levels the halves to the one scrolled last, which the view remembers.

### Find

`selectCurrentMatch(reveal:)` gains the sideways half: after the vertical
scroll, if the match's x range is outside its column's visible text width, the
column's offset is set to bring it in with a few characters of margin. Linked,
the other half takes the same offset.

### Resetting

`setDiff` and the arrangement switch set every offset to 0, before the find
reveal runs — so a search on the new diff can still move it.

## Risks / Trade-offs

- **[A fallback glyph makes a line wider than measured]** → the top-twenty
  measurement above, and a fixture that checks it.
- **[The bar covers the last row]** → the intrinsic height grows by the bar's
  height while it shows.
- **[Overlay scrollers are invisible until scrolled]** — with the system's
  "show scroll bars: automatically", `NSScroller` in the overlay style is hidden
  until used, so the reader still may not know the line goes on. → The bar uses
  the legacy style at the regular size while there is something to scroll, so
  the scroller is always visible then. Looked at beside the overlay vertical
  scroller in screenshots of both hosts: a 15-point strip with a separator above
  it, which reads as part of the diff rather than as a foreign control. The
  small size (11 points) was tried first and was too thin to notice.
- **[Cost per frame]** — one subtraction per text draw and hit-test. Nothing per
  row is added outside the rebuild's top-twenty measurement.
