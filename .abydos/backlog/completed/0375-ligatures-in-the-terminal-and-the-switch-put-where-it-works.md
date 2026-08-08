# Ligatures in the terminal, and the switch put where it works

`f2f15ae5c` · 2026-08-08

`NSAttributedString.ligature` is the obvious lever and it is the wrong
one. It governs the ligatures of prose — fi, fl — and setting it to zero
leaves `->` joined exactly as before. Measured on Fira Code: `->` shapes
to glyphs [1186, 1458] with the attribute at 0, at 1, and absent alike.
Only `calt = 0` on the font gives back the plain [1221, 1580]. So the
switch lives on the font, which is also the right place — every
measurement and every draw then agrees without being told separately.

The same measurement settled how to draw them. These fonts substitute one
glyph's shape for another rather than merging cells: `->` is two glyphs
before and two after. That is deliberate, and it is why a terminal can
have ligatures at all — the cell count never changes, so the grid never
moves. The first attempt looked for a drop in the glyph count and so
rejected every case that works.

So the terminal shapes a run to find out *which* glyphs to draw, and
decides for itself where each goes: at its own character's column, whole
points, exactly as before. Both renderers. Shaping is asked for only
where two ligature-forming marks sit side by side, which is nearly no run
of prose, and what comes back is remembered per run and face — a terminal
draws the same prompt and the same operators over and over.

The test asserts the property that would have caught the first mistake:
with ligatures off, shaping gives back exactly the font's own
per-character glyphs. That holds for any font, vacuously for one with no
ligatures and entirely for one with them.
