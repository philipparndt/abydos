## Context

`TerminalMetalRenderer` builds one `CellInstance` per cell and draws them all
with one instanced `drawPrimitives`. The vertex shader makes each instance's
quad the union of its cell and its glyph; the fragment shader paints the
background over the whole quad and the glyph's coverage over that. Instances
are drawn in array order, row by row, left to right, with straight-alpha
blending. So the cell to the right of a spilling glyph paints its opaque
background after the glyph, and over it.

`TerminalView`'s CoreGraphics path fills backgrounds first and draws glyph runs
afterwards, and is right.

## Goals / Non-Goals

**Goals:**

- A glyph that reaches past its cell is drawn whole, whatever the cell after it
  holds.
- A cell's background colour stops at its own edge.

**Non-Goals:**

- Fitting wide symbols into their cell, as Ghostty constrains private-use
  glyphs. That changes what a symbol looks like; this change only stops it
  being cut. It may still be worth doing for the Nerd Font icons, and would be
  a change of its own.
- Touching character widths. These marks are one column in tmux and in Ghostty,
  and the emulator agrees.

## Decisions

**Two passes over one buffer, selected by a uniform.** The first pass returns
the background inside the cell's rectangle and transparent outside it; the
second returns the glyph's foreground with the glyph's coverage as alpha, and
transparent where there is no glyph. The instance buffer, the pipeline and the
textures are bound once; only the uniform changes between the two draws.

*Ruled out: sorting instances so glyph cells come last.* Two cells with
spilling glyphs still order one over the other, and a rule about order is a rule
the next feature forgets.

*Ruled out: clipping the glyph to its cell.* That is the fault, made
deliberate.

*Ruled out: a second pipeline state.* One fragment function with a branch on a
uniform is a constant branch across a draw; two pipelines would be two shaders
to keep in step for one `if`.

**The background stops at the cell.** A new `withinCell` varying, computed
before the bell's wobble so the fill moves with the quad, gates the first pass.
The single pass painted the background over the union quad, which coloured a
neighbour's cell whenever the glyph leaned into it — invisible while both cells
shared a colour, and a real smear at the edge of a coloured prompt segment.

**Colour glyphs divide their alpha back out.** The atlas holds emoji
premultiplied and the pipeline blends straight alpha; the single pass blended
by hand against `in.background`. Over a first pass that has already painted the
background, the second pass hands the pipeline `rgb / a` with alpha `a`.

**The bell's aberration keeps its hand blend.** Three channels sampled apart
need three alphas, which one blend state cannot give; it still mixes against
`in.background`, which is what the first pass put under it except across a
neighbour's overflow while the bell rings. Acceptable for an effect that lasts
a second.

## Risks / Trade-offs

**Fragment work doubles for cell quads** → It is the smallest of the GPU's
costs here, and the renderer exists because the CPU path's problem was count,
not weight.

**Underlines and rules are instances with no glyph** → They draw in the first
pass, under glyphs. An underline under a descender is the ordinary look.

**`Uniforms` is shared across the Swift and Metal boundary** → Both gain one
`float` at the end; `setVertexBytes` sends `MemoryLayout.stride`, and both
sides pad to 32 bytes.

## What the second look found

**The colour follows the glyph.** The first two-pass shader painted every
background inside its cell and every glyph as ink alone, and a black diamond on
a yellow prompt segment ran into the dark cell beside it black on black — its
right half gone again, to the eye. Reported the same afternoon: "the background
should span the complete character". So the glyph pass paints the glyph's box
in its own cell's background under the ink, the full height of the row across
the cell and as far sideways as the glyph reaches; a glyph-high box left dark
strips above and below the overhang, which was the second report. A cell with no
glyph paints nothing in that pass, which a third cut showed was not optional.
