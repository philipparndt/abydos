# Make return keep the indent and close the braces

`c950217b6` · 2026-08-01

Return put the caret at column zero, so every line of every block had to be
indented by hand. It now keeps the current indent, adds a level after
anything that opens one — a brace, a bracket, a paren, or a trailing colon,
which is the whole of Python's block syntax — and pressing it between a pair
puts the closing half on its own line with the caret on a blank line between
them.

Typing a closing brace on an otherwise blank line pulls that line back a
level so it lines up with what opened the block, rather than with its
contents. Only on an otherwise blank line: `items[0]` must not reindent as
it is typed.

Tabs or spaces is decided by what the file already does rather than by the
setting, looking at the top of it. Joining a tab-indented file and filling it
with spaces is worse than either convention on its own.

Verified by typing a nested block with no manual indentation and reading
back what landed in the document.
