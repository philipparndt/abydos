# Name the debugger's buttons, and put it in the tool strip

`c0f9c01bc` · 2026-08-01

Five small arrows in a row that mean quite different things, and no icon set
has ever made that obvious: each one says what it is and which key does it
when you hover it. Step over now arcs over the call rather than pointing
down-right, which read as stepping into one.

The debugger has a button at the bottom of the tool strip beside the
terminal, since that is where its panel lives and where somebody looks for
it. It lights while a session is running, so the strip says something is
being debugged even when the panel is closed, and pressing it with nothing
running starts a session rather than opening an empty panel.

Stop is ⌘F2, which is what IDEA uses and what the tooltip claims.
