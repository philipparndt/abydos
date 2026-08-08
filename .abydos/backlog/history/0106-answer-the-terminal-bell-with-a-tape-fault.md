# Answer the terminal bell with a tape fault

`2efbe47dd` · 2026-08-01

An option, beside the colour scheme: Sound, VHS, or Ignore. VHS shakes the
picture sideways and splits the text into its colour channels for about two
thirds of a second, the way a worn tape does when the tracking slips.

Two shader changes rather than a post-processing pass. The wobble moves the
geometry — rows slide by an amount that varies down the screen and crawls
upward — which costs nothing, since the vertices were being transformed
anyway. The fringing samples the glyph's coverage three times, a little
apart, so each channel gets its own idea of where the ink is. That is what
the lens error actually looks like, and it costs two texture reads instead
of a second render target.

Each sample is held inside its own glyph's slot in the atlas. The atlas is
packed tight, so one that wanders out picks up whichever letter is next
door, and one that wanders off the edge comes back empty and takes a whole
channel of the text with it — which is exactly what the first version did.

It decays as a curve, so most of the movement is early and the last of it
fades rather than stopping. It needs the GPU renderer, being a shader; with
that off the beep stands in rather than the bell doing nothing at all.
