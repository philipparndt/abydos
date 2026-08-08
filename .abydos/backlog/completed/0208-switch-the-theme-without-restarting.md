# Switch the theme without restarting

`5e38d0435` · 2026-08-03

Changing the appearance repainted almost nothing: everything that reads the
palette as it draws was fine, and everything that *copied* a colour when it
was built — a layer's background, a table's, a text field's — kept the one it
was born with. There are ninety-odd of those, and chasing each by hand is how
a theme switch ends up nearly working.

So the swap recognises the colours themselves. Anything holding a colour from
the palette that was in use is handed the same role from the palette that has
taken over, alpha and all; a colour from anywhere else is left alone. The
sidebar pane is rebuilt rather than swapped, since it is cheap to make and
picks its shades as it builds.

Two things were pinned to darkness and are not any more: the app's own
appearance, which is why the popup in the settings was white on white, and
the project switcher's popover.

And the terminal changes with it. The scheme that follows the editor already
did; the Ghostty-blue one now has a daylight face — the same hues with their
values pushed down so they can be read on paper-white — on a background that
keeps a hint of the blue, because a terminal exactly the colour of the editor
beside it stops reading as a terminal.

Checked by switching at runtime rather than by launching twice: the window
goes from dark to light in place, terminal included.
