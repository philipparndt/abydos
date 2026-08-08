# Fix terminal device attributes, add mouse reporting, remove flicker

`31b4562ae` · 2026-07-30

Three problems surfaced by running tmux and starship in the pane:

Stray "^[[?6c" on screen. Primary and secondary device attribute queries are
different questions and were both answered with a primary response. tmux and
powerlevel10k were parsing for something else, so the reply fell through to the
shell, which echoed it as literal input. They now answer separately, and DSR 5n
and DECRQM are answered too rather than leaving programs waiting.

Mouse did not work. Added tracking modes 1000/1002/1003 with SGR encoding
(1006), and forwarding of press, release, drag, right-click and wheel. SGR is
what modern programs request because the legacy encoding cannot address past
column 223. Shift is the conventional override that keeps the event for the
terminal. On the alternate screen the wheel drives the program's cursor, since
there is no scrollback to move through.

Flicker. A full-screen program repaints via many small writes, and redrawing on
each one tears the screen mid-update. Repaints now coalesce to one per runloop
turn, and on the alternate screen the view no longer resizes or autoscrolls,
which was fighting the program's own painting.

Also fixes powerline separators rendering as blank boxes: they are Private Use
Area glyphs that SF Mono has none for. The terminal font now carries a cascade
list to whichever Nerd Font is installed, and the font is configurable.

102 tests.
