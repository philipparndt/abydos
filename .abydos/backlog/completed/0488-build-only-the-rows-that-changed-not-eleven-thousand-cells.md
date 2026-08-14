# 488. Build only the rows that changed, not eleven thousand cells a frame

`ABYDOS_METAL_PROBE=1` during a fire benchmark, on the reporter's machine:

    renders=43  cells/render=11750  parse=505ms  build=250ms  drawable=1ms  encode=8ms

**`cells/render` is 11,750 and it never moves.** That is 250 columns × 47 rows: every
cell handed to the renderer every frame, whether it changed or not. It costs 250 ms of
every second — a quarter of the machine — and the GPU that receives it is asleep at 9 ms.

## Why this is the cheap half

`takeDirtyRange()` already exists on `TerminalEngine`, already reports the rows that
moved since it was last asked, and taking it already clears it. **`TerminalDirtyRangeTests`
already pins what it reports** — 0487 added it precisely because "the renderer draws
every row where it used to draw one" was a suspected cause of a regression, and it is
in `make test`.

So the machinery, the tests and the invariant are all here. What is missing is the
renderer using them.

## What to be careful about, because a wrong answer here is invisible

- **A dirty *range* is not a dirty *set*.** One line printed at the top and one at the
  bottom is a range covering the whole screen. Whether that matters for the fire (which
  dirties everything anyway) and for real output (which usually dirties the bottom
  rows) is worth measuring rather than assuming — the win may be large for logs and
  nil for the fire, and the fire is what is being benchmarked.
- **The cursor moves without a row changing**, and so do the selection, the hovered
  link and the visual bell. A row that only lost the cursor still has to be rebuilt.
- **Reflow and scrollback eviction shift absolute row indices**, which is what
  `discardedLineCount` is for and what `realignSelectionForDiscardedLines` already
  reckons with.
- **Metal keeps the instance buffer between frames**, so rows that are not rebuilt must
  still be *there* from last time — this is a change to how the buffer is filled, not
  only to how much is computed.

## The number to beat

250 ms/s at 43 renders is 5.8 ms a frame. The frame budget for 60 Hz is 16.7 ms and
the frame currently costs about 17.5, so **this alone should reach 60**; for 120 the
parse has to come down too, which is item 0489.

Measure with the same instrument that found it, and say the load: `ABYDOS_METAL_PROBE=1`
gives `renders`, `cells/render` and `build` directly, and `cells/render` falling below
the grid size is the proof the change did what it says.

## How it works, and why it reaches further than the title

A kept row cannot be built in the window's coordinates. Output arriving at the
bottom of a view that follows it moves the whole picture up by a row, and so does
a line falling out of history — so every cell on screen would have to be built
again in order to *move* it, which is the work this item exists to stop. So:

- **Cells are built in document coordinates and the scroll offset is one
  uniform.** `float2 scroll` in `Uniforms`, subtracted at the top of `cellVertex`
  before anything reads a position — including the bell's wobble, which is a
  function of where a row is on screen. Pixel-identical, because the inset and the
  cell are whole numbers of points and `round(K - o) == K - round(o)` for integer
  `K`; only the offset is rounded now, and it was the only fractional part.
- **Rows are filed under a line number, not an absolute row.** Absolute rows are
  scrollback-plus-grid indices and every discarded line renumbers all of them.
  `TerminalDirtyRows` in AbydosKit does that conversion and the union across
  parse batches, and it is unit-tested — the renderer itself has no test target.
  Coordinates are measured from a `documentBase` that moves once every 32,768
  discarded lines, so a `Float` never has to hold a number it cannot.
- **The atlas got a `generation`.** A kept row holds normalised coordinates into a
  texture it does not own; emptying the atlas moves every glyph in it, and
  `setCellMetrics` empties it. Anything else a kept row assumed and cannot check —
  cell size, inset, palette, scale, faces, ligature setting, the picture cutouts,
  the hovered link — is one `RowContext` compared per frame, and a difference
  drops the lot.
- **The cursor is the one thing that changes a row without the engine writing to
  it**, because a block cursor turns its cell inside out as the row is built. The
  row it arrives on and the row it left are dropped from the cache whenever the
  cursor differs from last frame, by line number rather than by absolute row. The
  selection and the outlined cursor are laid over the cells afterwards and need
  nothing; the bell is a uniform; the hovered link is in the context above.
- **`repaint()` drops every kept row.** All fifteen of its callers are saying the
  whole picture may differ for a reason the engine cannot report — a theme, a
  font, the keyboard arriving, a link under the pointer — and none of them is on
  the output path.
- **A row off screen is dropped, every frame.** Not for memory: output goes on
  arriving at the bottom while somebody reads history further up, and the range
  that said so is taken by a frame that had no reason to build those rows. What a
  kept row is allowed to mean is exactly "it was on screen when the last frame was
  built, and every range since has been asked".

### The three lines in `TerminalEmulator`, which is 0489's file

Named precisely so the merge is legible. `screen.markAllDirty()`, once in
`setAlternateScreen` and once in `reset()` — both of which swap the whole grid for
another one and take its dirty range with it, so every row on screen becomes a
different row and nothing said so. Nowhere near the parse path: no `write`, no
`setASCII`, no `setCell`. Neither draw path had ever needed it — the document's
height changes when the scrollback comes and goes, and AppKit repaints a view
whose frame changed — which is why nothing said so and nothing failed.
`TerminalDirtyRangeTests.takingOverTheScreenDirtiesEverything` says it now.

## What it does now, measured

Both columns out of **one binary**, a minute apart, same window, same load:
`ABYDOS_METAL_ROW_CACHE=0` builds every row of every frame as the renderer did
before this item, and unset keeps the rows the engine did not report. That switch
exists because of the morning 0487 spent reading two numbers from two binaries
whose benchmark body had changed in between.

Release build, 232 × 47 = **10,904 cells**, GPU path, our engine, throwaway
bundle id and defaults domain, load stated per table.

**`status` — one row rewritten in place, the shape of a progress bar, a clock, a
status line, vim's ruler and a shell echoing a keystroke.** Load 5.9–7.4 over ten
cores (0.6–0.7 per core):

| | renders | cells/render | rows/render | instances/render | build |
|---|---|---|---|---|---|
| every row, as before | 60 | 10,904 | 47 | 10,904 | 390 ms (6.5 ms/frame) |
| only what changed | 46 | **232** | **1** | 10,904 | **22 ms (0.5 ms/frame)** |

**47× fewer cells and 18× less build**, and `instances/render` stays at the whole
screen — which is the proof that the rows nobody rebuilt are still in the buffer
from the frame that did.

**`fire` — every cell of the screen changes every frame.** Load 15–22 over ten
cores, which is high and is why the ratio is quoted per cell rather than the
absolutes:

| | renders | cells/render | rows/render | build | per cell |
|---|---|---|---|---|---|
| every row, as before | 55 | 10,904 | 47 | 331 ms | 552 ns |
| only what changed | 60 | 11,511 | 49 | 366 ms | 530 ns |

**Nothing, and nothing lost.** The fire dirties every row of every frame, so
there is no row to keep; the range spans the screen and the cost per cell is the
same within 4%. Confirmed against the true before, on the old binary at load
5.1–7.9: 39–47 renders, 10,904 cells, 213–257 ms build — **5.47 ms/frame, against
5.5 ms/frame after**. (The two `fire` runs above had windows three rows apart,
47 and 50, which is why cells/render differs and why the comparison is per cell.)

**`plain` — a screenful of log a frame, flat out.** Identical before and after:
**1 render a second**, 10,904 cells, 47 rows, **build 2 ms**, parse 650 ms. There
was never anything here to win, and that is the finding: `RedrawThrottle` gives a
flooding program one frame a second, and in that second the whole screen really
has changed. The 250 ms/s this item was filed on is the fire's alone.

So `cells/render` falls below the grid size on a screen that changes in part, and
does not move on one that does not — which is what the item asked to be measured
rather than assumed, and it went the way the item guessed.

### The number to beat, honestly

It is not reached, and this change was never going to reach it. 250 ms/s of build
is the fire's, the fire has no unchanged rows, and 5.5 ms a frame of building
10,904 cells is 500 ns a cell however few frames want it. What this buys is every
*other* screen: the terminal somebody is actually looking at, where a keystroke,
a spinner or a status line changes one row out of fifty.

The fire's own 500 ns a cell is now the thing to pull on, and it is not the dirty
range. Suspected, unmeasured, and left as a note rather than a claim: `ligatures(in:)`
runs per row per frame and walks runs of equal attributes, and every cell of the
fire has a different background colour — so the runs are one cell long and the
scan is a lazy map and a `mayLigate` per cell. Worth an item of its own.

## Steps

- [x] The renderer builds from `takeDirtyRange` rather than the whole grid
- [x] Everything that changes a row without the engine writing to it — cursor,
      selection, hover, bell — still forces that row
- [x] Rows that are not rebuilt survive in the instance buffer
- [x] `cells/render` falls, measured, with `renders` and `build` beside it
- [x] A dirty range spanning the screen is no slower than today
- [x] A pattern in `abydos-bench` that changes part of a screen, since none of
      the seven did and the class this item is about had nothing to measure it
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` only if behaviour changed — a faster identical picture may
      need no delta, and saying so is an answer

## What was ruled out on the way

- **A dirty range being a range and not a set.** The thing the item said to
  measure rather than assume, and it never once cost anything: across every load
  above, `rows/render` was either 1 or all of them. The pattern that would punish
  it — one line at the top and one at the bottom — does not seem to be a shape
  real programs produce, and no measurement here found one. Not fixed, and the fix
  if somebody ever does find one is a set of rows rather than a range, which is a
  change to the engine's side of the seam.
- **The eviction case, which is the honest limit of this change.** A line falling
  out of history marks the whole document dirty in `TerminalScreen.scrollUp`,
  because absolute rows shift and a range of them is the only vocabulary it has to
  say so. The renderer no longer needs to be told — it works in line numbers, and
  nothing it holds moved — and it is told anyway, so a terminal whose 5,000 lines
  of history are full builds every row for every line printed. Deliberately not
  changed: it is `TerminalScreen`, which 0489 is in, and it would rewrite an
  invariant 0487 pinned on purpose. `TerminalDirtyRowsTests.aDiscardedLineIsStill
  TheWholeDocument` pins the limit so the next person argues with a test rather
  than discovering it. Worth an item; the win would be the `history` pattern and
  every long-lived terminal.
- **Comparing a row's contents to decide whether to rebuild it.** This is what
  would win the fire — the top third of a doom fire is black and identical frame
  to frame, marked dirty because the program wrote it. Not done: the item asks for
  the range, and the two ways of doing it both cost something on the path 0489 is
  measuring. Holding the previous `TerminalLine` makes the array non-unique, so
  the next write to that row copies it inside `setASCII`; hashing the cells costs
  reading all 10,904 of them per frame, which is most of what a range check
  avoids. Either might still be worth it, and both belong to whoever picks up the
  500 ns a cell.
- **`plain` as the load that would show the win.** It cannot: it renders once a
  second and its build is already 2 ms. Two hours went on measuring loads that
  turn out to change the whole screen between frames — which every one of the
  seven `abydos-bench` patterns does, because that is what makes them benchmarks.
  Hence the eighth.
- **The instance buffer being rewritten in place.** Considered and not done. Rows
  have different instance counts — an underline or a strikethrough adds one — so a
  row whose count changed shifts everything after it, and the copy that avoids is
  a memcpy of 1.1 MB the upload already does. Measured instead: the fire is within
  4% per cell of the old path, which is that memcpy's whole cost.

## Two traps that cost an hour each, for whoever measures this next

- **`renders=0` with everything working.** AppKit stops a view's display link when
  its window is not visible, and the GPU path draws on that clock — so a benchmark
  run behind another window renders nothing, reports zeroes for `build`, `drawable`
  and `encode`, *and screenshots perfectly*, because `--screenshot` draws the
  CoreGraphics path and cannot see the Metal layer. An hour went on hunting a
  regression that was a window. The geometry line now answers it: `gpu=`, `link=`
  and `onScreen=`. Launch through `open` rather than by running the binary — on
  macOS 14 an app started by a shell that is not frontmost cannot take the focus —
  and treat any second with `renders=0` as a second nobody could see.
- **The pane's `abydos-bench` is not the one you built.** `PseudoTerminal`
  *appends* the app's own `bin` to `PATH`, deliberately, so `/usr/local/bin/abydos-bench`
  from an earlier `make install-cli` wins. A new `--mode` gets `--mode is one of …`
  and the run goes quiet. Call
  `build/Abydos.app/Contents/Resources/bin/abydos-bench` by path.

**No spec delta**, for the reason 0472 and 0487 had none: the picture is
identical, and `spec/` is the account of what the program does rather than of
what it costs. Two things in it did change and neither is a requirement — the
geometry line a test harness prints now says `gpu=`, `link=` and `onScreen=`, and
`abydos-bench` has an eighth pattern. If the spec ever grows a requirement about
what a frame may cost, this is the item it should cite.
