# Make the terminal keep drawing under a program that floods it

`57391d2ca` · 2026-07-31

DOOM-fire showed a frame every few seconds and the window would not respond,
while the program's own counter claimed 953 fps. Both were true: we were
accepting 84 MB/s and painting almost none of it.

Every chunk read from the pty was parsed on the main thread the moment it
arrived. Because we always drained the pty, the program never blocked, so it
produced as fast as it could and the main thread spent every cycle parsing —
a second of wall clock held ten seconds of queued parsing, and the view drew
zero times. Making the parser faster made this worse, since it let the writer
go faster still.

Output is now queued and parsed a few milliseconds at a time, yielding
between helpings so the screen can be drawn and keys can be read. Once the
backlog passes a few megabytes, reading from the pty stops until it drains;
the bytes stay in the pty's buffer and the program writing to it blocks. That
back-pressure is what a terminal is supposed to do — it is how a program is
told it is going faster than anyone can look.

Reads are also gathered rather than delivered one at a time. A frame arrives
as hundreds of small writes, and hopping between queues for each of them cost
more than the bytes cost to parse.

The same fire now runs at 384 fps in a small pane and 46 fps full screen,
with the fire actually moving. Ghostty does 400 full screen, so there is
still a long way to go, and it is in the renderer now rather than here.
