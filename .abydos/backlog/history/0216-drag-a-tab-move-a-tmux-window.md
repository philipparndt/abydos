# Drag a tab, move a tmux window

`57c7d4d15` · 2026-08-03

tmux reorders properly — `move-window -b` and `-a` insert before or after a
target and push the rest along — so a dragged tab is a real reorder rather
than a swap of two, and the windows are renumbered afterwards so the indices
stay the positions they look like.

Which side depends on the direction dragged, because that is what the gap the
tab was dropped into looked like. The strip reorders itself before tmux
answers, for the same reason a clicked tab highlights itself.

Checked against tmux directly: one, two, three; drag the first to the end and
it is two, three, one; drag it back and it is one, two, three.

Tearing a mirrored tab out into a window of its own does nothing now — that
would mean a second client attached to the same session, which is not what
the drag looked like it would do.
