# Build cell colours without going through NSColor

`5eff0026a` · 2026-08-01

The instance builder asked TerminalPalette for an NSColor and converted it to
components, twice per cell — a colour-space conversion for the foreground and
another for the background, ten thousand times a frame.

The palette is now also kept as the numbers the shaders want, worked out
once, and a truecolour cell is arithmetic rather than an NSColor built and
thrown away. Dimming is a multiply on the alpha instead of asking for another
colour.

Honest note: this does not move the fire benchmark, which colours its cells
from the 256-entry palette — already a lookup. It removes an allocation per
cell on truecolour screens, which is what a program drawing gradients emits,
and takes NSColor off the per-cell path either way.
