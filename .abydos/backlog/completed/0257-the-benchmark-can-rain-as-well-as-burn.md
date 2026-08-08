# The benchmark can rain as well as burn

`40a5d7bc6` · 2026-08-04

The fire puts one glyph in every cell and a new colour in every cell, so
what it measures is how fast colours can be changed. A terminal that
rasterises one block and tints it sails through, and nothing in the
benchmark notices that it never drew a second shape.

`--mode matrix` is the other half. Half-width katakana and digits, one
cell each, hundreds of different ones on screen at once, moving down
rather than changing colour — and a flicker that swaps glyphs where they
stand, which is the part that cannot be cached: a cell that changed
colour may be the same picture tinted, and a cell that changed glyph
never is. Trails age by where their head has got to rather than once a
frame, so a slow column keeps a full-length trail instead of one that
dies just behind it.

The two land differently, which is the point of having both. At 100x30
in a release build: the fire 296 fps at 63 kB a frame, the rain 1027 fps
at 9 kB — one bound by the bytes, the other by the glyphs. Same summary
line, same refusal to run into a pipe, same restored terminal.
