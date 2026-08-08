# A launch configuration says what is wrong with it before it is run

`33472e9ed` · 2026-08-06

Three warnings, and each one is a failure that happened here this week and
cost an hour, because none of them fails anywhere near the configuration:

A Go package with the LLDB debugger starts nothing and says nothing — the
adapter reports no event, the watchdog gives up, and what it looks like is a
broken debugger or a permissions problem. An argument naming a file that is
not there is passed through as written, so the program complains about *its*
configuration rather than about this one. A file listed to send that is not
there is skipped in silence, and the pod starts without it.

Warnings rather than errors: a path can be produced by the build, an argument
can be a flag that looks like a path, and something half-written should not be
shouted at. Each names its field, since the list sits above them — "Nothing at
nowhere" is a puzzle, "Working directory: nothing at nowhere" is an
instruction.

And paths can be chosen rather than remembered. A configuration is shared, so
what it needs is not the path a chooser returns but that path written with a
variable; the chooser opens where the field already points and writes back
`${workspaceFolder}/…`, or `${userHome}/…` for a tool that lives on this
machine. The three variables and what they stand for are spelled out where
they are used, instead of one example of one of them.
