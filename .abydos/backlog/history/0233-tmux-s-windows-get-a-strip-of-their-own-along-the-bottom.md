# tmux's windows get a strip of their own along the bottom

`0077059ea` · 2026-08-03

An experiment, behind two settings. tmux's windows move to a strip under
the terminal — numbered rather than iconned, since the number is what
`C-b 2` selects and an icon saying "terminal" on a strip of nothing but
terminals says nothing, and in the palette's green so they read as the
thing inside the terminal rather than as more of the app's chrome. The
top strip goes back to being what the panel holds: the tmux terminal as
one ordinary closable tab beside the debugger and the profiler. Closing
it costs nothing — the session and its windows carry on without it.

Each + now means what it is next to: the top one opens another terminal
of ours, the bottom one a tmux window. Killing a window is on the menu
only, and now actually reaches tmux — the new strip had no `onClose` at
all, so the menu item did nothing.

tmux's own status bar is hidden without touching tmux: the pane is
reported as many rows taller as `#{status}` says the session has status
lines, and those rows are never drawn. Nothing is written to anybody's
.tmux.conf, every other client attached to the same session keeps its
bar, and somebody who has already turned theirs off gets no phantom row
and no gap. Turning the session option off instead — the obvious first
try — both changed a session other terminals share and left the old bar
painted on a row tmux had stopped repainting.
