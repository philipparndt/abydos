# Debug anything, and attach to what is already running

`c83afb06b` · 2026-08-01

The debugger was Go-only, which was never a protocol limitation — the
adapter protocol is the same whichever debugger is behind it. What differed
was a handful of strings, and those now live with the adapter: which program
to run, whether it speaks over a socket or its own pipes, what it expects to
be called, and the shape of the launch request.

So LLDB drives C, C++, Rust, Swift and anything else that compiles to a
binary, through exactly the same panes. "Debug Executable…" picks one; the
adapter is chosen by what the project is, since a go.mod above the program
means Delve and anything else means LLDB, and deciding that is better than
asking.

"Attach to Process…" covers what launching cannot: a server that is already
up, or something that only misbehaves after an hour. The list leaves out the
system's own daemons, because a list with every one of those in it is a list
nothing can be found in.

Fixed while doing it: the window's wiring lived at the Go entry point, so a
session started any other way ran perfectly and told the editor nothing —
no execution marker, no breakpoint state. Every way of starting one goes
through the same wiring now.

Verified against lldb-dap on a C program: stopped at the breakpoint, stack
of three frames, locals, watches, and the thread picker.
