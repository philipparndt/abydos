# Turn the cell under the cursor inside out

`eba9f4f12` · 2026-08-01

The character the cursor sits on was unreadable. A translucent block was laid
over it, which leaves the character the same colour as what is now behind it —
so the one place you are looking is the one place you cannot read.

A block cursor inverts instead: the block is the cursor's colour and the
character is cut out of it in the colour behind. Both renderers do it; the
CoreGraphics one draws the character again over the block rather than
compositing.

The offscreen shot draws the cursor whatever has focus, since a window
rendered offscreen has none and the cursor is worth being able to look at.
