# The tmux strip dims, and the green means one thing again

`6088f274c` · 2026-08-04

Full strength across the whole foot of the window, tmux's green was the
loudest thing on screen — a bar shouting for attention it does not want,
and which nothing else in the app could then be louder than. It is the
shape that is recognised, not the saturation, so the bar is now the same
hue sunk into the terminal's own background: still plainly tmux, and
plainly part of the terminal rather than part of the app.

That leaves the green itself free to mean one thing — which window you are
in — so it stays at full strength on the number and on the line along the
top of the selected tab.

The ink follows the bar rather than being chosen alongside it. How far the
green is dimmed is a number somebody will want to turn, and a theme's green
can be any green at all; picking either black or white to go on it would
eventually be ink the same colour as the thing it is written on.

And the first tab starts hard against the left edge. The layout already
closed the gaps *between* tabs on this strip for the reason that a sliver
of green down the side of the tab you are in looks like a frame around it —
the leading inset was left behind, and framed the first tab alone.
