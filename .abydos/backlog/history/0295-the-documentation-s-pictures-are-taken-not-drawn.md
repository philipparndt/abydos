# The documentation's pictures are taken, not drawn

`89f73b9d3` · 2026-08-05

`make screenshots` photographs the app against the examples repository: the
editor on a Go service, a breakpoint stopped in it, tmux as the panel's tabs,
and a Maven project. Every one is the app doing the thing the page claims
beside it, on a project anybody can clone and try.

Each shot copies its example to a temporary directory first. Opening a project
writes a session file into it, and a subdirectory of a git repository resolves
to the repository root — so photographing `examples/go-service` in place would
both litter the examples and open the whole repository with whatever was last
left open in it.

No git shot for that reason: a copy has no `.git`, and a changes pane
photographed empty says the opposite of what it is for.
