# Hand over the frame with the layout change, and honour synchronised output

`ed5cb201f` · 2026-08-01

Two things about a resize showing something it should not.

The layer now presents with the transaction: the new contents and the new
size become visible together, rather than the old contents being stretched to
the new size until the next frame happens along. That is what the mode is for,
and it also needs the frame handed over here rather than by the command
buffer — waited until the GPU has the work, then presented.

Mode 2026 is implemented rather than merely answered. A program about to
rewrite a lot of the screen says so first and says when it has finished; what
is on the grid in between is half-drawn, a pane erased but not yet filled in,
and drawing that is what makes a repaint flicker. tmux and full-screen tools
use it, but only when the terminal says it has it — so the mode query now
answers properly instead of pleading ignorance, which is what it did before.

A frame is held for at most a tenth of a second, so a program that sets the
mode and then stops cannot freeze the screen.

An earlier attempt at this made it worse and is gone: redrawing the instant
the drawable changed size presented a frame whose contents were still laid
out for the grid the pane used to have.
