# Strict tmux: the tabs are tmux's windows

`20286bb79` · 2026-08-03

One terminal, one shell, one pty — and a tab strip that is a view of the tmux
session rather than a list of terminals of our own. Clicking a tab is
`select-window`; the + is `new-window`; closing one is `kill-window`;
renaming one renames the window. Nothing is torn down or built to change
tabs, which is the point: switching costs a message to tmux and a repaint.

It goes the other way too. A window switched inside tmux — by its own keys,
by another client — moves the tab, and a window renamed there renames the
tab. Watched by asking rather than by being told: tmux will run a hook, but a
hook has to find its way back into this process, and asking twice a second
costs a millisecond of a shell nobody is waiting on.

The window list is read with semicolons for separators, since tmux replaces a
tab in a format with an underscore — the same lesson as the pane path — and
the name is whatever is left of the line, because a window can be called
anything.

Verified from both ends: three windows named shell, editing and build showed
up as three tabs, and `tmux select-window -t m3:2` from outside moved the
highlight to `build`.

Also, the terminal is arranged the way the setting asks once per window
rather than on every project it opens. Opening another project in the same
window is not a window opening, and having the terminal take the screen again
in the middle of switching is a jump nobody asked for.
