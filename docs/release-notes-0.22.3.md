# Abydos 0.22.3

## A lane of several tracks opens into them

Drawn as *Notes*, a stem whose layer holds more than one track has a chevron
after its name. Closed, it draws its tracks in one strip as before; a click on
the chevron, or on the tracks listed beside it, opens it into a strip per
track, each named, and the other lanes give way. It stays open across renders.
*Wave*, *Spectrum* and *Both* are unchanged: a stem is one sound.

## A block is muted from its region

Drawn as *Notes*, a right-click on a region has a menu: *Mute Block*, *Go to
Play Line* and *Go to Pattern*. Muting writes `mute` at the end of the block's
`play` line and saves the file; the block keeps its place, so nothing after it
moves, and it is drawn empty with a broken edge. It needs a `mat` that knows
the word: build and install it from musik-as-text 4c678d7 or later.

