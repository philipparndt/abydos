# Write plain text in runs, and remember character widths

`aa0369e7a` · 2026-07-31

Plain output goes from 1.8 to 3.0 MB/s, fire from 3.6 to 4.2.

Two costs on the write path. Establishing a character's width meant
consulting the Unicode property tables, for every character written,
including ASCII — so a byte per code point of the Basic Multilingual Plane
now remembers the answer, and ASCII skips even that.

The other was writing a character at a time: a Character built for each
byte, handed to the screen, stored through a bounds check and a
copy-on-write check of its own. Text arrives in runs, so a run of printable
ASCII is now cut to the row and written straight into the cells. The wrap
is deferred exactly as it was for single characters, which is what keeps a
line of exactly the terminal's width from wrapping a column early.
