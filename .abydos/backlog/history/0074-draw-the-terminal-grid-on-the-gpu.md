# Draw the terminal grid on the GPU

`f378e5eb4` · 2026-08-01

The groundwork: a glyph atlas, shaders, and a renderer that turns a screen of
cells into one instanced draw call. Not yet wired to the view — this is the
part that can be checked on its own.

What made CoreGraphics slow was never the work, it was the count of it: ten
thousand rectangle fills and ten thousand glyph draws for a screen where
every cell has its own colour. Here each cell is one instance of a quad, the
glyph is coverage sampled from a texture, and the colours come from the
instance — so a screen where every cell differs costs the same as one where
none do.

Glyphs are rasterised once, on demand, into a shared texture: a terminal
shows a few hundred distinct characters however long it runs. Anything the
terminal's own face cannot draw is looked up through CoreText's fallback and
kept with the font that had it.

Verified by rendering to a texture and writing a PNG, since Metal draws into
a layer the window-capture path cannot see — --metal-shot does this, and it
caught the one real bug so far: the quad covers the cell and the glyph
together, so the corners outside the glyph were sampling past its place in
the atlas and stamping slivers of whichever letter had been packed beside it.

Known gap: the atlas holds coverage, so a colour emoji comes out grey. That
needs a second atlas in colour, and the cell has to say which one it wants.
