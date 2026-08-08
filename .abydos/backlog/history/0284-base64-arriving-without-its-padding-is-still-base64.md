# Base64 arriving without its padding is still base64

`2954d31cd` · 2026-08-05

`kitten icat` renders nothing. Neither did `chafa` on a file it happened to
pick a file transfer for. `timg` was fine, and so was the script I had been
checking against — which is exactly why this survived being written, run and
looked at.

kitty leaves the `=` off the end of its base64. `Data(base64Encoded:)` refuses
anything whose length is not a multiple of four, so the payload decoded to nil
and the picture was dropped on the floor. A path is rarely a multiple of three
bytes long, so the file transfer mediums hit it essentially always; a direct
transfer only hits it when the image itself is not a multiple of three bytes,
which is why one client worked and another did not, and why my own script —
`base64(1)`, which always pads — never showed it at all.

The padding is put back rather than demanded of the sender. Stray characters
are dropped first, since a chunk may carry a newline and the padding has to be
counted from what is really there.

Found by installing the real clients instead of trusting my own reading of the
spec: `kitten icat --transfer-mode=stream` drew the picture and
`--transfer-mode=file` drew nothing, which named the seam exactly.
