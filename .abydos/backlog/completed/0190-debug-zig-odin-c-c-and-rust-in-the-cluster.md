# Debug Zig, Odin, C, C++ and Rust in the cluster

`bf2f0e31c` · 2026-08-02

Delve is Go's debugger and knows nothing about anything else, so a native
program in a pod is held by gdbserver — 640 KB and three libraries, taken
from Alpine — and driven by the LLDB already on this machine. The binary
stays here as well: it was built here, so its debug information names these
sources and every breakpoint, frame and variable lands where it should
without a source map.

    push  →  gdbserver --no-startup-with-shell :2345 /app/current
    forward 2345  →  lldb-dap here: target create <the binary>
                                    gdb-remote 127.0.0.1:<port>

--no-startup-with-shell because the image has no shell; without it gdbserver
execs /bin/sh, dies saying so, and reads as a broken debugger rather than a
small image. That was the first thing this taught me, and the second was that
a stale supervisor silently runs the program instead of the debugger.

Verified by stopping in the cluster: c-hello paused at main.c:21 with the line
lit in the editor, zig-hello inside its loop at main.zig:11.

And the image can be smaller, since a pod only ever debugs one language:
`make image VARIANT=native` is 13 MB against 32, `VARIANT=go` 27 MB, and
`make publish-all` pushes all three. The chart runs the full one, so nothing
has to be chosen for it to work.
