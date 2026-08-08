# Repaint the lines that changed, not the whole terminal

`ef031b27d` · 2026-07-31

A printed line costs 0.18 ms instead of 2.21 ms — twelve times less.

Any change marked the whole view for display, so a single line of output
repainted every visible row, and AppKit could not keep any of what it
already had. The screen now records which lines changed, as absolute indices
into scrollback-plus-grid rather than grid rows: a line keeps its place in
the document as history grows, so scrolling appends a line at the bottom
instead of moving everything, and printing dirties one row.

Anything that moves lines rather than rewrites them — a restricted scroll
region, a resize, history overflowing and shifting every index — marks
everything, so the fallback is the old behaviour rather than a stale screen.
Past half a screenful it marks everything anyway, since working out what to
keep costs more than painting it.

The cursor is drawn over a cell that is otherwise unchanged, so the row it
leaves is repainted along with the row it arrives on.

Also caches the four faces a cell can ask for. Deriving bold or italic goes
through NSFontManager, which was being asked once per run of every frame,
and the advance behind it came from a dictionary that allocated its key on
every lookup. A full frame goes from 2.31 to 2.02 ms on its own.
