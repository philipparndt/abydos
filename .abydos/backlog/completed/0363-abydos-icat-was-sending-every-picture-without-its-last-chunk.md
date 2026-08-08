# abydos-icat was sending every picture without its last chunk

`a4fed5c43` · 2026-08-07

`base64 | tr -d '\n'` is one unterminated line, so `fold` ends its last
line without a newline — and `read` returns false on a line with no
newline even though it read one. The loop body was skipped and that piece
was never sent. Every picture arrived a few kilobytes short, no terminal
could decode it, and what came out was the space the image would have
taken with nothing in it. In Ghostty as readily as here: the stream was
wrong, not the terminal.

It survived being looked at because the one image I checked it against
encoded to exactly fifty-seven whole chunks, so there was no partial last
line to lose. Anything else — which is every real picture — lost its tail.

`|| [ -n "$piece" ]` sends it.

The test runs the script and compares what came off the wire with the
file, byte for byte, on a size deliberately chosen not to divide into
whole chunks. Nothing on the Swift side of the pipe could have caught
this; only reading what the script actually wrote.
