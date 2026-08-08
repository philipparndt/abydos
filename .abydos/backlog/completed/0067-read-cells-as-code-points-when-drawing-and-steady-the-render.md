# Read cells as code points when drawing, and steady the render benchmark

`fc4841d6d` · 2026-07-31

A full frame goes from 1.83 to 1.68 ms.

Drawing rebuilt a Character out of every cell to look at its first scalar —
the same cost that was taken off the write path, still on the draw path,
once per cell of every run. A cell holds the code point, so it is read
directly.

The render benchmark now takes the best of several rounds rather than the
mean. This machine was running a load average of fifty at one point, which
moved the mean by a factor of two — enough to invent regressions and hide
real ones. It also reports what a single row costs, which is what a printed
line costs now that only what changed is painted.

Where the rest of a frame goes, measured by holding the text back: drawing
the text is 1.48 ms of the 1.73, and the whole rest of the frame —
backgrounds, separators, selection — is 0.25. So a glyph cache drawn
through CTFontDrawGlyphs is the next thing worth doing, and nothing else in
the frame is worth touching before it.
