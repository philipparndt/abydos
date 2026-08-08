# Any two panes side by side, and a way that is not a gesture

`851de8865` · 2026-08-02

The drop preview appeared and the drop did nothing. A destination view under
a terminal is at the mercy of a hit test through whatever the program is
drawing, so the overlay is now only a sheet of glass that draws: where a drop
lands is decided by the strip, from where the pointer was let go. That path
was already there for tearing off; it decides all of them now.

And a tab has a menu: Put Beside, Left / Right; Show One Only; Rename; Move
to a Window; Close. A gesture that has to be learned is a gesture that can be
missed, and this is the same code the drag runs.

Every pane can be moved, not only a terminal — a profiler beside the terminal
that produced the load is the arrangement somebody wants, and a debugger
beside its program is another. A window of its own stays terminal-only: a
debugger belongs to the window whose program it stopped.
