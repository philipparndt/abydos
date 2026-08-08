# Put the GPU path back on the pixel grid

`84f829685` · 2026-08-01

Three things were off, all of them about landing on whole pixels.

Powerline separators were drawn as font glyphs. The CoreGraphics path draws
them as geometry filling the cell, deliberately — a font sizes them to its
own metrics and they never quite fill it, which leaves a seam where one
prompt segment meets the next. The same geometry is now rasterised into the
atlas at cell size and stamped like any other glyph, so the arrow reaches
both edges again.

Cell edges were raw floats. Each cell's far edge is now the next cell's near
edge, both rounded to whole points, as the CoreGraphics path already did —
otherwise neighbouring backgrounds miss each other by a fraction of a pixel
and a dark line runs down the middle of a prompt.

Glyphs were placed at a rounded cell edge plus an unrounded bearing, which
lands them on a different fraction of a pixel in every cell and resamples
each one differently. They are snapped to the pixel grid now, which is what
made ordinary text look unevenly spaced.
