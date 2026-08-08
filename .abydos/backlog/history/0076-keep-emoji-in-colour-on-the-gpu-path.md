# Keep emoji in colour on the GPU path

`ca746d0dd` · 2026-08-01

The atlas held coverage, one byte a pixel, which is all an ordinary glyph
needs: the cell's foreground shows through it. An emoji carries its own
colours and came out grey.

There are two sheets now. A glyph from a colour font — which CoreText will
say plainly — is rasterised into a smaller BGRA sheet and composited over the
cell rather than used as a mask. Smaller because a terminal shows a handful
of emoji and each costs four bytes a pixel instead of one.
