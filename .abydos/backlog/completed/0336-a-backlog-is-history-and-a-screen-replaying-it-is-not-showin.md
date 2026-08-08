# A backlog is history, and a screen replaying it is not showing the program

`8971022b0` · 2026-08-07

Coming back to a terminal that has been running unwatched, the console
flickered and an agent's clock sprinted through the minutes it had spent
while nobody was looking. The parsing was right; the drawing was not. Every
picture drawn during catch-up has already been replaced by the time it
reaches the screen, and drawing them in order replays time that has passed.

While behind, the screen is now left alone: nothing at all for the first
quarter of a second, which swallows the catch-up after a locked screen or an
app switch, and after that a heartbeat of one picture a second rather than
twenty. The picture that matters is the one drawn when the backlog drains,
and that one is never skipped.

A flood and a burst cannot be told apart while they are happening — a minute
of buffered frames arrives from the kernel exactly as fast as a program that
never stops writing — so both are treated the same way, and the rate is
chosen for what it costs to be wrong. A coarser picture of a build is a
smaller price than the flicker this exists to stop, and one a second is
still plainly alive.

Measured through the path output actually takes: forty thousand frames of a
spinner and a clock drew seventy-nine pictures before and eleven after.
