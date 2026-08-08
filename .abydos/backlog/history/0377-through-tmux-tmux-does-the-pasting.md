# Through tmux, tmux does the pasting

`f01a2a238` · 2026-08-08

Bracketed paste is a promise to the program reading the keyboard: what
follows arrived at once, so do not run every line of it. Through tmux
there are two such programs — tmux, which asks for the markers so it can
receive a paste, and whatever is in the pane, which asks separately and
changes its mind constantly. A shell turns them off while a command runs
and on while it is editing a line, and the capture in
Fixtures/return-burst.bin shows it doing exactly that on every prompt.

What this terminal sees is tmux's answer, so writing the markers here is
answering the wrong program. Losing that race is how `^[[200~` ends up in
the command line, and why it only happens sometimes.

So tmux is handed the text — `load-buffer` from standard input, so
nothing has to be quoted, then `paste-buffer -p` — and it brackets the
text or does not according to what the pane actually asked for. There is
no longer a race to lose. Outside tmux nothing changes.

The test runs a real tmux with a pane writing to a file, and checks both
that the text arrives and that no markers arrive with it.
