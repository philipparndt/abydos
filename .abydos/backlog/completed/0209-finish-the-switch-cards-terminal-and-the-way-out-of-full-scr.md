# Finish the switch: cards, terminal, and the way out of full screen

`351300eff` · 2026-08-03

Three things the palette change was still missing.

The panels that keep their colour and put it back on every display pass were
being handed a new one and undoing it a moment later — which is why the
settings cards stayed dark while the labels on them went light. They are told
now rather than poked.

The terminal's own colours are the scheme's, not the theme's, so no amount of
recognising palette colours would have caught them; the palette is thrown
away and rebuilt, and every terminal re-reads it. The daylight ANSI table is
also kinder now: a middle lightness, because a terminal colour is as often a
background as a foreground — a powerline prompt is nothing but coloured
backgrounds — and black is properly black, since a prompt writes it on top of
its own colours.

And opening a page while the terminal has the whole window gives the window
back. The editor is hidden in that mode rather than merely small, so settings
opened behind it: asking for a page is asking to look at it. Arrowing through
a file tree in a popover does not count — only opening something for good.
