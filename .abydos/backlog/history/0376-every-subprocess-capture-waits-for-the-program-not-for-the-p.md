# Every subprocess capture waits for the program, not for the pipe

`dbba39ace` · 2026-08-08

The two-pipe deadlock was fixed where it had actually bitten; these are
the rest. Each read one pipe to the end and then waited for the process,
which is safe from that particular deadlock and not from the other one:
end of file needs every copy of the write end closed, and Foundation does
not mark a pipe's descriptors close-on-exec, so any long-lived subprocess
started while this one was being set up pins it open. A stray `/bin/cat`
did exactly that this afternoon and hung the suite for twenty minutes.

tmux, the shell's working directory, the language server registry, Xcode's
destinations and the debug adapters all go through ProcessPipes now,
which waits for the program and then takes the descriptor away from a
reader that is waiting on somebody else.

UserShell is left alone: it already waits with a deadline and kills the
shell when it passes, which is the same idea with a marker protocol
wrapped around it.
