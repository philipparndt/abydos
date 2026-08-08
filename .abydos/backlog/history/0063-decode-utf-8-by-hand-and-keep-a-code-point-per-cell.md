# Decode UTF-8 by hand, and keep a code point per cell

`90e82eb4b` · 2026-07-31

Non-ASCII text goes from 1.9 to 6.4 MB/s, and the fire benchmark from 3.7 to
6.0 — past the 4.4 MB/s a 60fps fire needs, having started at 0.9.

Each byte of a sequence was appended to an array and the whole array run
through the standard decoder to see whether it was complete yet, so a
three-byte character built three iterators and three decoders and allocated
along the way. The sequence is now assembled as it arrives: shift in six
bits per continuation byte and emit when the count runs out. Overlong
encodings, surrogate halves and anything past the last plane are shown as a
replacement rather than accepted, which the standard decoder did for us and
is now covered by tests, along with truncated sequences and stray
continuation bytes.

Cells hold a code point rather than a Character. Building a Character means
building a String with the grapheme breaking that implies, and a grid is
written to far more often than it is read. The rare cell that really is a
cluster — a base with combining marks — keeps the string alongside, and the
`character` property assembles what to draw from whichever of the two is
there, so nothing that reads a cell had to change.
