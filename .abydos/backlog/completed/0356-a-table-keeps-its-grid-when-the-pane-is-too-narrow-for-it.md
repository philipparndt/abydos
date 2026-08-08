# A table keeps its grid when the pane is too narrow for it

`183aa175c` · 2026-08-07

Cells were padded with spaces and joined with bars, which is a grid only
while nothing wraps. In a pane narrower than the widest row every long
cell wrapped back to the left margin, and three columns read as a
paragraph with bars in it.

They are laid out as a real text table now, one block per cell, so a
long sentence wraps inside its own column. Each cell goes through the
inline renderer as well: a link in a table was showing as its markup.

The first cell has to open a paragraph of its own — a paragraph takes
the style of its first character, so a cell appended to an unterminated
heading joined that heading, which put "file" beside "The diagrams" and
shifted every column one to the left.
