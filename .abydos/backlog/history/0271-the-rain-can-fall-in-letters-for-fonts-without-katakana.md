# The rain can fall in letters, for fonts without katakana

`5d0540c80` · 2026-08-04

Half-width katakana is what the film's rain is usually approximated with,
and it is what this reaches for — but only a font that has those glyphs can
draw them, and a terminal that will not fall back to one draws nothing at
all. In Ghostty the whole screen came out as scattered digits: every cell
drawn, and every katakana among them blank.

Blank cells are not a benchmark of anything — the glyph cache is the thing
this mode exists to press on — so `--ascii` asks for letters and digits
instead, which is the one alphabet no font can be missing.
