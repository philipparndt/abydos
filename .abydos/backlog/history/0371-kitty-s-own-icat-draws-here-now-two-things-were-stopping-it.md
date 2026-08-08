# kitty's own icat draws here now: two things were stopping it

`8efac01d8` · 2026-08-08

Both found by feeding kitty's real byte stream into the emulator and
looking at what came out.

**The colour was never read.** kitty names the image in the placeholder
cells' foreground colour, written `ESC[38:2:r:g:b` with colons — which is
what the standard specifies. We read only `ESC[38;2;r;g;b` with
semicolons, which is what almost everything else writes, so the cells had
no colour, no id, and stood for no picture. Both spellings now, including
the long colon form that names a colour space first.

**The image was never received.** The APC cap was 8192 bytes, set on the
strength of the protocol saying a chunk should be at most 4096 bytes of
base64. kitty's icat does not follow its own recommendation when it
believes the terminal can cope: it sent this image in two chunks of
131072. Everything past 8192 was swallowed, the base64 was truncated and
the PNG never decoded. The cap is eight megabytes now — far past any real
chunk and still a bound, with what a picture costs capped separately by
the image store once it is decoded.

And a sequence that does run past the cap is dropped whole rather than
acted on short. A truncated payload is a picture that fails to decode, or
worse one that decodes to something wrong, and neither says why.
