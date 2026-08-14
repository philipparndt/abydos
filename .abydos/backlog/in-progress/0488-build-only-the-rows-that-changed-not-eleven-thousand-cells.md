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

## Estimate

2026-08-14 08:09 — about four hours left; baseline reproduced at cells/render=10904

## Steps

- [ ] The renderer builds from `takeDirtyRange` rather than the whole grid
- [ ] Everything that changes a row without the engine writing to it — cursor,
      selection, hover, bell — still forces that row
- [ ] Rows that are not rebuilt survive in the instance buffer
- [ ] `cells/render` falls, measured, with `renders` and `build` beside it
- [ ] A dirty range spanning the screen is no slower than today
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed — a faster identical picture may
      need no delta, and saying so is an answer
