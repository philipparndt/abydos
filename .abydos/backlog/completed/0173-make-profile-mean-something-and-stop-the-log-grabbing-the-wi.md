# Make Profile mean something, and stop the log grabbing the window

`d81af7909` · 2026-08-02

The profiler opened but was never pointed at anything: it took an address
when it was created and waited to be asked. Profile now runs the
configuration and, when the program is up, forwards the pod's pprof port and
connects — one sequence rather than a guess at how long a build takes. A
profiler that is already open is re-pointed at the new run rather than left
showing the last one's port.

The pod's log was pulling itself in front once a second, which made every
other tab unreachable. It is brought forward when a launch begins and not
again; the same for the launch log.

The launch page shows all four ways to start — run, debug, profile, cover —
since the room is there and that page is where somebody is deciding what a
configuration does.

Two things from using it: an external edit now tells the language server, so
a problem fixed by an agent stops being reported in red afterwards; and an
agent starts with edits accepted, since one that stops to ask whether it may
change the file it was asked to change has not been asked anything. Settings
has the other two modes.
