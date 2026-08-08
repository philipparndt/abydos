# Every + in a tmux panel makes a tmux window

`c1dde9be6` · 2026-08-04

I hardened the wrong button last time. The one being pressed was the panel's
own strip, up top, whose first tab *is* the tmux terminal — and that one had
the second meaning: "another terminal of ours", chosen by whether tmux's
windows happened to be drawn on a strip of their own. So pressing it put
plain shells into a window that is supposed to be the session, and no amount
of pressing produced the window it looked like it would.

Both strips now call one function, and it can only make a window. The
condition that decides is whether this panel is a view of tmux at all —
not that, plus a preference about where the tabs are drawn. A panel not
mirroring tmux still adds a terminal, which is the only thing a + can mean
there.

`--tab-add` prints the pane count either side of the press, as `--tmux-add`
already did. "panes 1 -> 1, windows 2" from both buttons is the guarantee,
and it is now the thing the harness actually looks at.
