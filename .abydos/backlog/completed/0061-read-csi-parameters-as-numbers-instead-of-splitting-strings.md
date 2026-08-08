# Read CSI parameters as numbers instead of splitting strings

`881823025` · 2026-07-31

Fire goes from 0.9 to 3.6 MB/s, plain output from 1.2 to 1.8.

Parameters were collected into a Swift String, one Character per digit, then
split on ";", each piece split again on ":", and every piece run through
Int(). That happened on every read of a parameter, and a sequence reads
several — CUP alone re-parsed the whole buffer twice. A truecolour SGR
arrives for every cell of a full-screen repaint, so this was most of what
the parser did.

Digits are folded into an integer as they arrive now, into a flat array of
values with the boundaries of each ";" component alongside, so subparameters
still work and nothing allocates per sequence. The introducer and the
intermediate bytes are kept as bytes rather than recovered from the front of
a string.

The benchmarks are off unless IDEAI_BENCH is set. They saturate a core for
as long as they run, which was enough to make a timing-sensitive test
elsewhere fail when the suite ran them alongside it.
