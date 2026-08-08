# Breakpoints outlive the window, and a disabled one stays disabled

`c49be17ce` · 2026-08-06

Three things about breakpoints, all of them the same complaint: a breakpoint
is a note about where to look, and it kept not being there later.

They were never written down. The session file held what was open, which
terminal was where and what the play button pointed at, and nothing about the
gutter — so closing a project swept it. They are in the session now, with
their conditions and hit counts, written as they change rather than only when
the window closes: a note that costs a moment to place is worth nothing after
a restart that took it.

A disabled one came back enabled. Starting a session replayed each breakpoint
as a toggle, and a toggle builds a fresh breakpoint, which is enabled — so one
somebody had deliberately switched off was switched on, sent to the adapter,
and stopped there. The session adopts the set whole instead, which also keeps
the log message and hit count that the replay had to put back by hand.

And dragging one out of the gutter deleted it the moment the pointer passed
the threshold, before the mouse button came up, with no way back but to place
it again. The cursor now says what letting go would do, and letting go is what
does it — drag back over the gutter and the breakpoint stays.

Also, the terminal has no left margin: an inset made the panel read as a
document with a gutter rather than a screen.
