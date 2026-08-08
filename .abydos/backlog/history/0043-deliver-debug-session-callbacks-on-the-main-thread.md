# Deliver debug-session callbacks on the main thread

`ed882f0f4` · 2026-07-31

Hitting a breakpoint aborted the process. The adapter's replies resume on
a cooperative-pool thread, and every one of the session's callbacks ends
up in AppKit: the stopped handler opened the file and moved the
execution marker from there, modifying the layout engine off the main
thread, which aborts rather than merely misbehaving. Every callback now
hops to main first.

That crash is also proof the rest works: to reach it, Delve had to build
the program, bind the breakpoint, stop on it, and report a stack. Three
things had to be fixed for that to happen at all:

- Breakpoints were registered after the launch task had started. The
  adapter asks for them once, between `initialized` and
  `configurationDone`, and both arrive within milliseconds — anything
  later is simply too late, and the program ran to completion. They go
  in with the session now.

- They were keyed by a path Foundation had rewritten. `standardizedFileURL`
  applies the same `/private` special case as `resolvingSymlinksInPath`,
  so a breakpoint was filed under `/tmp/x` while the debugger reported
  `/private/tmp/x`. It was set, verified against nothing, and never hit.
  Both sides use realpath(3) now, through one shared helper.

- The adapter's stdout was read only until the port was found, then left
  unread — which is where the debuggee's own output comes out. The
  program's `hello` now reaches the console.
