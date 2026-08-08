# Let the terminal take the whole window

`081f9dd51` · 2026-08-01

Beside the chevron that puts the panel away, an arrow that gives it
everything: the tree, the editors and their tabs all go, and the panel's own
tabs stay, since they are how you get between terminals. Also on View as
Maximize Terminal, shift-cmd-J.

The window draws under its own titlebar, which never mattered for a panel
sitting along the bottom. Reaching the top it does, so the tab strip takes
the same inset the tree and the editors take, and follows it into and out of
full screen.

Putting the panel away while it is maximised also puts the window back
together, or reopening it would find nothing above it.

Written for measuring: the terminal benchmarks are only comparable against
another terminal at the same size, and this is how the pane gets to a size
worth comparing — 153x38 here against 153x11 with the editors showing.
