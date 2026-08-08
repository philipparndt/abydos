# A picture is sized here, in both dimensions, and fits the window

`931517e75` · 2026-08-07

Two things, both about the gap after the image.

The protocol will take a width alone and keep the proportions — and then
only the terminal knows how many rows that came to, while this has to
move the cursor past them. Working it back out from the cell size is
close and not exact, and every cell it is out by is a blank line after
the picture. Both dimensions are sent now, so the terminal draws exactly
the box named here and the cursor goes exactly that far. There is nothing
left to guess.

And the height is fitted to the window as the width already was. A
photograph is thousands of pixels across; a portrait one is taller than
the screen, and printing its height in newlines scrolled it away before
anybody had seen it. One line short of the window, so the prompt that
follows is not already scrolling the top of it off.

Only when no size was asked for: somebody who types -w 200 means it.
