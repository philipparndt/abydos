# The geometry report says whether the clip view has been scaled

`9251b3a28` · 2026-08-08

A grid twice the visible width is what a scaled clip view produces: its
bounds are its frame divided by the scale, and dividing that by a cell
gives twice as many columns as fit. The report gave only the bounds, so
there was no way to tell that apart from an honest wide pane. It gives
both now, and the backing scale beside them.

Which turned out to say the geometry is right, at every width tried —
but the next person to doubt it can see the three numbers together
instead of inferring from one.
