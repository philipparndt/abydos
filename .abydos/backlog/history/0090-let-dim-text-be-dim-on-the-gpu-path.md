# Let dim text be dim on the GPU path

`74e2326fe` · 2026-08-01

Claude Code's greyed-out suggestion came out as bright as what had been
typed. Truecolour and the 256-entry palette were fine; dim was not.

Dim is drawn by asking for a faded foreground, and the shader mixed the
glyph's coverage between background and foreground while ignoring the
foreground's own alpha — so a colour asked for at sixty per cent arrived at a
hundred. The alpha is part of the mix now.

--metal-shot honours --delay, since the shot was firing before the command
under test had printed anything.
