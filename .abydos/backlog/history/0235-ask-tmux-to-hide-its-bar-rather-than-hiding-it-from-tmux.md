# Ask tmux to hide its bar, rather than hiding it from tmux

`39e614eea` · 2026-08-03

The clever version is gone. Reporting the pane a line taller and never
drawing that line worked in a screenshot and not in use: tmux paints its
bar once at attach and then stops repainting a row it no longer owns, so
whatever was on it at that moment showed through for the rest of the
session. Every path that walked rows had to know about the phantom one,
and one of them always forgot — the GPU renderer drew it for a week.

So the settings ask instead. A button under Terminal turns tmux's status
bar off by adding a marked block to ~/.tmux.conf, and turns it back on by
taking that block out; the running server is told either way so nothing
has to be reloaded. The file is backed up first, the block says what it
is and how to undo it by hand, and a config without our block is never
touched — including somebody's own `set -g status off`, which is theirs
and stays.
