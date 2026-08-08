# Dispatch CSI sequences on the byte, not a Character

`ab89372b6` · 2026-07-31

Fire goes from 6.0 to 6.2 MB/s, plain output from 2.9 to 3.1.

The final byte of a sequence was wrapped in a Character and matched against
character literals, so every escape sequence went through grapheme
comparison to decide between a couple of dozen single-byte cases. The letter
each byte stands for is now a comment, which is all it was ever needed for.
