# Debug what a make goal would have run

`2d14b7563` · 2026-08-01

`make dev` builds a frontend, builds a Go binary with -ldflags "-s -w",
and runs it with a config path and two credentials out of sops. All of
that is worth keeping except one part: the binary make produces has no
symbols, so a debugger attached to it can say nothing.

So the work is divided. Everything that is not the Go build still runs
through make, because that is what the project says those steps are, and
the Go package is left to the debugger, which builds it with the symbols
it needs. The program then starts with the arguments the recipe passes
and the environment it sets — including the assignments whose values come
out of a shell, evaluated at launch because nothing else can evaluate
them.

The goals appear in the run menu; choosing one writes an ordinary
launch.json entry with two keys of ours that anything else ignores.
