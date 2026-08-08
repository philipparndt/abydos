# Which palette and how light are two questions, so they are asked separately

`4bc5a02d9` · 2026-08-07

The theme list had five entries to say four things — Abydos, Abydos Light,
Dark, Light, System — and still could not say the fifth: Abydos, following the
system. Somebody who wants the warm palette wants it in the morning too, and
somebody who follows the system wants the palette they chose to follow along
rather than be swapped for another one.

So: which palette (Abydos or Blue), and how light (System, Light, Dark). The
stored value is still one string, because everything downstream — presentation
mode, the `--theme` flag, the palette lookup — has always been handed one, and
every value that could have been stored before decomposes into the pair that
means the same thing now. That is the whole of the migration.

The terminal keeps "Same as the theme", and each family now has a terminal
palette of its own rather than borrowing the editor's, so following survives
the light switch without being asked again. The scheme that does borrow them
is called "Editor colours" rather than "Dark", which beside a control asking
light or dark was answering the wrong question.

Also, unrelated but found while looking at a report of typing that ran off the
right-hand edge instead of wrapping: the grid is now checked against the pane
on every layout pass. Everything that resizes a pane or a cell already asks
for that, but a missed one is invisible until somebody types — the program is
told the width the pane used to be, writes to it, and every line overruns,
while the program's own idea of the text stays correct so pressing return
looks perfectly normal. The geometry report says the width now too, which it
never did.
