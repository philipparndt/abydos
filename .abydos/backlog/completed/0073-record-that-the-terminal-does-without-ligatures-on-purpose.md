# Record that the terminal does without ligatures on purpose

`7371fbed4` · 2026-08-01

The glyph path drew one glyph per cell and, as a side effect, stopped
turning `->` into an arrow. That was described as a loss when it landed; it
is wanted. A terminal is a grid, and shaping a run so a pair of characters
becomes one glyph is the same thing that lets text drift off it.
