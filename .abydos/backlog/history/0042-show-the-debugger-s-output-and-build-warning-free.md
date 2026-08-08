# Show the debugger's output, and build warning-free

`82e4354da` · 2026-07-31

The debug pane had nowhere to put the adapter's output. `debugOutput`
was a hook that nothing ever assigned, so every build error and every
line the program printed was dropped — a failed launch looked exactly
like one that simply had not stopped yet. There is a console now, wired
straight to the session, and it immediately showed a Delve complaint
that had been invisible all along.

A launch that produces no event within 25 seconds also reports itself,
naming macOS's developer-tools authorization as the usual cause: it
holds the debuggee until the prompt is answered, and with developer mode
off it asks every time.

Warnings cleared in all three builds:

- DAPClient is `@unchecked Sendable`. Process and socket callbacks arrive
  on background queues and have to reach it; the shared mutable state is
  behind its lock and the rest is set before any callback can run.
- An unused `git clean` result, an unused local, and a cast of a type to
  itself.
- The symbol tests carried a main-thread-only document across a
  `@Sendable` boundary; a box says so explicitly rather than silencing
  the whole module with `@preconcurrency`.
