# Give the alternate screen a document its own size

`a2ab2f3d9` · 2026-08-03

A terminal on the alternate screen kept whatever document height the
scrollback had when the program took over. Start tmux after a couple of
hundred lines of output and the document is four thousand points tall,
scrolled to the end, while the program draws its screenful at the top: the
terminal goes blank, or — when the mismatch is a single row — the last line
is somewhere below the window, which is where the cursor appeared to be on
the line above.

The alternate screen is one screenful and never scrolls, so the document is
now exactly the grid and the view sits at the top of it.

Reproduced first: `seq 1 200`, then tmux, and the pane was 3,636 points above
the visible rectangle. Same steps now show tmux.
