# Rasterise every glyph on the same pixel phase

`d44701e49` · 2026-08-01

Snapping where a glyph's bitmap goes was not enough, because each glyph was
drawn at a fractional position inside its own bitmap. A bearing is fractional
and differs per character, so every glyph came out rasterised at a different
fraction of a pixel — and no care about where the bitmap then lands can undo
that. Letters looked as though they sat on slightly different lines, which is
what an m next to an a showed plainly.

The drawing position is rounded to a whole pixel, and the offset recorded for
it is derived from where the glyph was actually drawn rather than from its
bounds, so the rounding is accounted for instead of fought.
