# The paths a container sees, and the ones this side has

`1117ad23b` · 2026-08-08

A renderer needs none of this — a diagram goes in on standard input and a
picture comes back, and neither mentions a file. A language server is the
opposite: almost everything it says is about a file, by URI, and the URIs
are the ones inside the container. Mount a project at /workspace and a
problem is reported in file:///workspace/src/main.go, which is a path
that does not exist on this machine.

This is the part of running a language server from an image that is worth
getting exactly right, and the reason it is written before any of the
rest. A mapping that is subtly wrong does not fail. It opens the wrong
file, or reports a diagnostic against nothing, and both look like the
language server being unreliable rather than like a bug with an address.

Anything outside the project maps to nothing rather than to a guess: the
container cannot see it, and a path invented inside would point the
server at the wrong file rather than at none. A sibling directory whose
name merely begins the same way is outside — the prefix bug every path
mapping has once, and it has a test. So does a space in a directory name,
which must not end a URI.
