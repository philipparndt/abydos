# Keep the byte stream that reproduces the blank rows

`513d57b65` · 2026-08-07

Captured from a live login shell: forty-five Return presses at key-repeat
speed, 9075 bytes. Replaying it into a bare emulator reproduces the blank
rows exactly, every time, with no view involved — which is what turns
"every now and then" into something that can be bisected.

Not used by a test yet. It is here because capturing it again means
another live shell and another burst, and the next person to look at #52
should not have to.
