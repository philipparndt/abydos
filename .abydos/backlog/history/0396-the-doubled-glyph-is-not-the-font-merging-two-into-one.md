# The doubled glyph is not the font merging two into one

`bcdb0e3e7` · 2026-08-08

Measured rather than assumed, since the assumption was mine and it was
wrong. Shaping `...`, `!!`, `->` and `==` with the bundled Nerd Font returns
one glyph per character, each with the same advance — the property the
shaping code relies on and says it relies on. So the ligature path is not
being handed fewer glyphs than cells, and the next person does not need to
spend an hour finding that out.

What is left is placement: two glyphs' worth of ink in one cell with the
neighbour still drawing its own is what an offset by a cell looks like, and
that is where to start. The four-line CoreText probe is in the entry, so it
can be pointed at whatever font somebody is actually using.
