# Take the language server's lock only from synchronous code

`e758b7eec` · 2026-08-01

The one place in the codebase the compiler had anything to say about, and it
was worth saying: NSLock taken inside an async function, which Swift 6 makes
an error rather than a warning. Holding a lock across a suspension point is
how a client like this deadlocks — the awaited work wants the same lock, and
nothing ever gives it back.

Each of the three critical sections is a couple of lines with no await in it,
so nothing was actually wrong; wrapping them in a synchronous helper keeps it
that way, and makes it visible that it is that way.

Worth noting for next time: an incremental build shows none of this. These
only appear on a build from scratch.
