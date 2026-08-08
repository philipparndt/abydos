# A broken pipe was killing the app outright

`a78c73716` · 2026-08-07

Exit status 141 — 128 plus 13, SIGPIPE. That is the whole of today's
mystery: the app disappearing several times an afternoon with no crash
report, nothing on standard error and no crash.log, because a process
killed by SIGPIPE leaves none of those. Every explanation offered for it,
including two of mine, was wrong.

By default a process that writes to a pipe whose read end has closed is
killed outright. This app writes to a pty every time somebody types, and
to a pipe for every git, language server, debug adapter and tmux command
it runs — so a shell that has just exited, or a tmux server that has
stopped, was fatal. Switching to a tmux tab whose server had gone did it
every time.

The handling was already written and had simply never run:
`PseudoTerminal.drainOnce` reads errno and drops what it cannot send, but
the signal kills the process during `write` before errno is ever looked
at. Ignoring SIGPIPE turns each of these into EPIPE and lets that code do
its job.

Set at launch, before anything goes near a descriptor, and again when a
pty starts so a tool that only links the kit is covered too.

The behavioural test writes to a pty whose program has gone. If this
regresses it takes the whole suite with it, which is the loudest failure
available and the right one — it is what the app did.
