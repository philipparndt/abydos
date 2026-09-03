## Why

Running `make test` in a pane drew swift-testing's pass and fail marks as their
left halves: a filled triangle and a thin angle where Ghostty, beside it, drew a
diamond with a tick and a diamond with a cross. Reported with both screenshots,
2026-09-02, and narrowed the same afternoon to the GPU renderer, with ligatures
on or off; the CoreGraphics renderer draws them whole.

The marks are Apple private-use characters from SF Compact, and the glyph is
13.7 points wide at 13 points against a cell of 7.8 — nearly two cells, and it
spills into the next one by design. The Metal renderer already allows for a
glyph reaching past its cell: the quad it draws is the union of the cell and
the glyph, and the blend state's own comment says it is straight alpha "so a
glyph reaching outside its cell blends with what its neighbour already put
there". What it did not allow for is the neighbour that comes *after*: every
cell is one instance of one draw call, drawn in order, and the next cell's
opaque background is painted after the glyph and over its overflow. The
CoreGraphics path never had the fault because it paints backgrounds before it
paints glyphs.

The same cut applies to anything that leans right — an italic, a wide accent,
a fallback glyph of any kind — and was reported before for other characters.
It went unreproduced here for an hour because a driven screenshot renders a
Metal pane through a CoreGraphics snapshot; `--metal-shot` reads the drawable
and showed it at once.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-02 — "running the test suite reveals a terminal rendering issue
of unicode characters … the clipping only happens with the GPU renderer".

## What Changes

- **The Metal renderer draws the cells twice.** The same instance buffer is
  drawn in two passes: the first paints every cell's background, each inside
  its own rectangle and nowhere else; the second paints every glyph over all of
  them, with the glyph's coverage as its alpha, so a neighbour's background
  shows around and under whatever reaches past the cell. A uniform says which
  pass the shader is in.
- A cell's background no longer bleeds into the neighbour its glyph leans into,
  which the single pass did do — harmlessly when both were the same colour.
- Nothing changes about which glyph is chosen, how wide a character is counted,
  or the CoreGraphics renderer.

## Capabilities

### Modified Capabilities

- `terminal`: gains a requirement that a glyph reaching past its cell is drawn
  whole under either renderer, and that a cell's colour stops at its edge.

## Impact

- **AbydosApp**: `TerminalShaders` gains a `pass` uniform, a `withinCell`
  varying and a two-branch fragment; `TerminalMetalRenderer` issues the draw
  twice. `Uniforms` grows by one float on both sides of the boundary.
- **Cost**: one more draw call per frame over the same buffer, and the
  fragment work of the cell quads once more. The GPU path exists because the
  count of work was never its problem.
- **Driver**: `--metal-shot` already captures the drawable, which is the only
  picture that shows the fault or its absence.
