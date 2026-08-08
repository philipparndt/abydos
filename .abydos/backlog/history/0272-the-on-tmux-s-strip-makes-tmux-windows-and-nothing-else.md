# The + on tmux's strip makes tmux windows, and nothing else

`1f38eb139` · 2026-08-04

It could make a plain terminal tab, and did — one in the panel's strip
above per press, which is what those repeated "ideai" and "Local" tabs
were.

The button checked whether *this app* had a live client before doing
anything, and opened a terminal instead when it decided it had not. That
condition was wrong often enough to matter, but the shape is the real
problem: a button labelled "new tmux window" had a second thing it could
do, so being wrong about the condition meant doing the other one silently.

Creating a window never needed a client. `tmux new-window -t <session>` is
answered by the server, and whether we happen to have a terminal looking at
that session is beside the point. So it asks for the window first, always,
and there is no path from this button to a plain tab while the session
exists.

Attaching survives only where it is the only option: the server refusing
means the session itself has gone — its last window closed — and making it
again is the one case that genuinely needs a client.

`--tmux-add` now prints the panel's pane count either side of the press.
"panes 1 -> 1, windows 2" is the whole guarantee in one line, and nothing
before this could see it.
