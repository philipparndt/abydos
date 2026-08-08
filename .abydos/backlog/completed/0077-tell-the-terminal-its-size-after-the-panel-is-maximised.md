# Tell the terminal its size after the panel is maximised

`e5f5158be` · 2026-08-01

tmux opened in a maximised panel drew for a window half the height of the one
it was in: it asked the pty how big the terminal was and got the size the
pane had before.

A resize normally arrives through layout, but layout reads the scroll view's
clip before the scroll view has laid it out. Dragging a divider sends a
stream of those and the last one is right; maximising sends one, reads the
size the pane had a moment ago, and nothing follows to correct it. The panel
now tells its terminals once layout has settled.

Double-clicking the empty part of the tab strip maximises and restores too,
the way double-clicking a title bar zooms a window.

Honest note: the harness reports the right size either way, so this addresses
the mechanism rather than a failure I could reproduce.
