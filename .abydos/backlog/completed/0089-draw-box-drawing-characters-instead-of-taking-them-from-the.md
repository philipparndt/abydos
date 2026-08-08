# Draw box-drawing characters instead of taking them from the font

`c0a11c1fc` · 2026-08-01

tmux borders and the rules Claude Code prints came out dashed, and the tree
in tmux's session list did not join up.

These characters exist to meet their neighbours, and a font cannot be relied
on for that: a glyph is sized to the font's metrics and a cell to a whole
number of points, so a rule drawn at its natural width leaves a fraction of a
point of background between one cell and the next.

Two attempts at fixing it from the font failed, and both are worth recording.
Stretching a glyph along whichever axis it nearly filled joined the rules but
pulled the corners off them, because a corner and a rule cover different
amounts of their cell. Mapping the font's own box onto the cell kept them
aligned but left the gaps, because the ink does not fill that box either.

So they are drawn: each character is a set of arms — left, right, up, down,
each light, heavy or double — filled to the cell rectangle. Every join meets
exactly and every arm lands on the same centre line, at any font or size.
Ghostty, Kitty and WezTerm all do this, for the same reason.

The first version drew them upside down: the context has y running up, so an
arm pointing up runs to maxY, not from minY. A tee is symmetric and looked
right, which is why it took a corner to notice.

The atlas also redraws when its drawable changes size, rather than waiting
for the next tick of the display link, which is what made a resize flicker.
