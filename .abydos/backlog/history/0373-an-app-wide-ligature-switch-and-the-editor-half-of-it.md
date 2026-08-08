# An app-wide ligature switch, and the editor half of it

`32b8a6880` · 2026-08-08

One switch rather than one per pane: a ligature is a decision about how
code should read, and reading `->` as an arrow in the editor and as two
characters in the terminal beside it is the arrangement nobody wants. On
by default, which is what the editor has always done — the terminal is
the one that will change.

The editor half is a line: CoreText ligates unless told not to, so the
attribute only ever turns it off.

The terminal half is not, and this is the groundwork for it. A terminal
draws a glyph per cell at a whole-point column because that is what keeps
text on the grid — the font's advance is fractional and a line left to lay
itself out creeps a whole cell across a typed command. Shaping is the
opposite of that, so it has to be asked for only where it can change
anything: `Ligatures.mayLigate` says whether a run has two of the
punctuation marks that ligatures are made of side by side, which almost
no run of prose does. What comes back from the shaper then has to be put
back on the grid rather than taken from it.

Also here because it was found on the way: an image shown through
placeholder cells has no entry in `placements`, so the eviction pass
counted every kitty-style picture as one nobody was looking at, and the
first squeeze on memory would have taken the one in front of somebody.
