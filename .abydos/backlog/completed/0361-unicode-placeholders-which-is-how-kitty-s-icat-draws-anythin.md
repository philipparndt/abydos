# Unicode placeholders, which is how kitty's icat draws anything

`901e6c8d9` · 2026-08-07

Sampling what kitty's own `icat` sends found `U=1` on every command and a
key we do not parse. It is the other half of the protocol: `U=1` makes a
*virtual* placement, one that belongs to no position at all, and the
picture is then shown by writing ordinary text made of U+10EEEE. Each of
those cells says which image it is part of — in its foreground colour —
and which of the image's cells it is, in two combining diacritics.

Ignoring the key meant reading the command as an ordinary place-at-the-
cursor, drawing the picture there, and then having kitty write its
placeholders over the top: the image appeared for an instant and was
gone. That is exactly what it looked like.

The indirection is the whole point, and it is also the answer to images
not surviving tmux scrollback. Placeholders are text, so everything that
moves text moves the picture: tmux is not re-sending anything when you
scroll back, it is moving characters, and a terminal that implements this
draws the picture wherever they land. Which is why it works in Ghostty
and did not here.

So the picture is worked out from the grid on every repaint rather than
remembered from where it was placed — one strip of the image per row of
cells, and a strip that starts part way along takes the matching part of
the picture. Both renderers, and the placeholder character is not drawn
as a glyph in either: it is a private-use codepoint no font has, so the
picture would arrive under a grid of missing-glyph boxes.

The diacritic table is kitty's own, copied rather than derived — it comes
from Unicode 6.0.0 with a handful of accents removed, and a terminal that
generated its own would agree only by accident.

This also supersedes the erase-a-picture-when-text-is-written-over-it
rule I had written for the tmux problem, which is now both unnecessary
and wrong: kitty does not delete an image because something was printed
over it, and with placeholders there is nothing stale left to clean up.
