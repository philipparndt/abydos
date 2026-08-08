# Follow the session on screen, and say which one it is

`26b12fdc2` · 2026-08-03

Two things about the mirrored strip.

It followed the session the window was opened with, so `C-b w` into another
session left the old session's tabs sitting there. It asks tmux which session
*this client* is looking at now — the same client-by-tty question the working
directory uses — and follows that. Switching sessions swaps the tabs;
switching back swaps them back.

And there is a tag beside the panel's own controls saying `tmux · name` while
the mode is on. The tabs look like our tabs, and it should be visible at a
glance that they are not: that closing one closes a tmux window, that another
client can move them, and which session they belong to. Just `tmux` when the
strip is too narrow for the name.

Checked by switching a client between two sessions from outside: `shell,
editing` became `notes, logs`.
