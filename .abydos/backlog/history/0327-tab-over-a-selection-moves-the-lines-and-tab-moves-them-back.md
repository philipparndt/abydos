# Tab over a selection moves the lines, and ⇧Tab moves them back

`ee59c0197` · 2026-08-06

Tab inserted a tab character wherever the caret was, so selecting a block and
pressing it replaced the block with a single tab — the selection gone and the
work with it, which costs an undo and a moment's fright. ⇧Tab did nothing at
all.

Now a selection that touches more than one line is a different gesture, as it
is in every editor: shift these lines, and keep them selected so it can be
pressed again. With nothing selected, Tab still inserts a tab and ⇧Tab takes a
level off the line the caret is on.

Outdenting takes a tab, or up to a tab's worth of spaces — a file indented
either way loses what looks like one level. A line already at the margin stays
there rather than being pulled into the line above, because ⇧Tab is not a
deletion. Blank lines inside a block are left blank rather than given trailing
whitespace nobody asked for.

Checked on a file with a tab, four spaces and no indentation on consecutive
lines: all three come back to the margin, and none of them further.
