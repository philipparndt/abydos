# Hold CSI parameters in storage of their own

`28a13c7ab` · 2026-08-01

Sequence-heavy output more than doubles: the fire benchmark parses at
142 MB/s against 56, colour changes alone at 178 against 55, and the whole
terminal now runs that benchmark at 474 fps against 279.

Parameters were collected into two arrays. An array checks that it is
uniquely referenced on every write, and a screen repaint sends two escape
sequences per cell — some ten thousand a frame — so that check came to more
than reading the digits it was guarding.

They are held in fixed storage instead, allocated once with the emulator. No
sequence anyone sends carries thirty-two components; anything longer is
dropped rather than grown into, which is what a terminal should do with a
sequence that is already nonsense.

Intermediates are checked before being cleared rather than cleared blindly,
since they are rare and that ran for every sequence too.

Plain text is unchanged at 21 MB/s, and ASCII at 42 — neither carries
sequences, so neither was paying for this.
