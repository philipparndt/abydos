# Put the debugger on the keyboard, and fix the build it never got to

`103566910` · 2026-08-01

Continue, pause, step over, step into, step out and stop are in the Run menu
on the function keys IDEA and Xcode both use, so the fingers that know them
already do not have to learn anything. They were reachable only from the
debug pane's toolbar, and a debugger you have to aim a mouse at to step is
one nobody steps. The commands grey out when nothing is being debugged
rather than sitting there doing nothing.

Stepping turned out never to have worked from a project under a symlinked
path, which is every project under /tmp and anything reached through one.
Delve builds with `go build`, and go compares the directory it is told to
build against the module it resolved: given `/tmp/x` for a module it knows as
`/private/tmp/x` it refuses with "outside main module", which reads as a
problem with the project and is not one. The package path is canonical now,
where it is resolved, so every caller gets it right.

Verified against Delve on a real program: stopped at the breakpoint, stepped
across two lines, stepped into the runtime, and stopped.
