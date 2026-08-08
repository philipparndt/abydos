# A project left because the terminal moved keeps its own window

`4aa5776ff` · 2026-08-08

Selecting another tmux window moved the shell into another checkout, which
is what following the terminal is for — and on the way out the project
being closed wrote down the window on screen as the one it was last in.
That window belonged to the project being opened.

So each project ended up remembering the other's window, and since opening
one selects the window it remembers, the two took turns: select a window,
the shell moves, the project follows, select a window. About once a second,
with nobody touching anything, and every switch reopening every editor tab
— including previews, each starting a container that then outlived it. It
was hard to get out of.

Both halves are fixed, and either alone would stop it. Nothing is written
down for the project being left when the terminal is what moved: whatever
it already had stands. And nothing is selected on the way in, for a reason
that holds on its own — the window showing is the one somebody chose a
moment ago, and moving off it is the app arguing with them about where they
are.

The rule is a function in ProjectSession with a test on it rather than a
condition at the call site, because what it prevents cannot be seen from
either end: each half looks reasonable, and the loop only exists between
them.

A regression from afa276e, which is what added the selecting.
