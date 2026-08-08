# Show what the program says, and the configurations that belong to the part being worked on

`d23c82149` · 2026-08-02

A service debugged locally printed nothing but Delve's own two lines while
plainly running. Delve does not forward the debuggee's output as protocol
events — it comes out of Delve's own streams, and only stdout was being read.
Go's `log` writes to stderr, and so does anything reporting a problem, so a
running service looked like a silent one. Both streams are drained now.

And the launch configurations page was reading the repository's folder rather
than the subproject's, which for a repository of several projects is a page
with nothing in it. It reads what the rest of the app reads: the part being
worked on.
