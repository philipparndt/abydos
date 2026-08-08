# A glyph painted twice, and where the settings page gets its width

`4877d207f` · 2026-08-08

Two entries, neither fixed.

The doubling is new and is reported in both the editor and a terminal pane,
which is the useful half: those do not share a renderer, so it is in what
they do share. Both ask the font what joins and then put the pieces back on
the grid, and both mark the cells a ligature covers so nothing draws them
twice — a piece landing on the wrong cell would leave one drawn by the
shaper and by itself, which is what it looks like. `!!` is worth suspecting
because it is not a ligature in these fonts: the run is shaped anyway, and
what comes back is two ordinary glyphs down the least-travelled path. The
switch is implicated by the person seeing it, so turning it off is both the
workaround and the confirmation.

And 387 gets what reading it turned up. The settings page pins its document
view to both sides of its clip view, so the content can never be narrower
than it wants to be — a 260-wide field, 190-wide pop-ups, a card constraint
that is a cap and not a floor — and that width leaves the scroll view and
reaches the split. Somebody has already lowered two compression resistances
there, which lowers the priority of the argument without ending it. Written
down rather than changed: the app has no test target, the divider is
interactive, and a layout change nobody can measure is how this sort of thing
gets worse.
