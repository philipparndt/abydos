# A program debugged in a cluster prints into our console too

`9f7605f1a` · 2026-08-07

The adapter's output events carry what the debugger says. A program in a
pod writes to the pod's stdout, which the debugger never sees — so the
console sat empty for a whole session while `kubectl logs` had the whole
story, and the only way to read it was to leave the app.

The supervisor's log is followed while the session lasts and appended to
the debug console, beside the debugger's own output. A run already had
this; it gets a tab of its own and keeps it.

The supervisor answers with a tail, which is the right thing for it to
answer and the wrong thing to append: ask twice in a second and the same
two hundred lines arrive twice. The run's tab could replace its whole
contents each time; a console cannot, because the debugger's output is
interleaved with the program's. So LogTail compares each answer with the
last and hands over only what follows the overlap — line by line, since
a tail is cut at whatever byte its window began at.
