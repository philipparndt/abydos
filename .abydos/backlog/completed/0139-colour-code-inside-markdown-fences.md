# Colour code inside markdown fences

`0110d3356` · 2026-08-01

The markdown grammar can only say "this is code", which left a whole
block one flat colour in both the editor and the preview. Each fence is
now parsed with the grammar it names — by the names people actually type
after the backticks, so sh, golang and c++ all land somewhere — and the
result painted over the markdown underneath.

The preview highlights a fence as a whole rather than run by run: a
string or a comment can span lines, and colouring one line at a time
ends them at every newline.
