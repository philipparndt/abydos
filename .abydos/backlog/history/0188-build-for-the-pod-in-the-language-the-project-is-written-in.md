# Build for the pod in the language the project is written in

`c99231a60` · 2026-08-02

Running in a cluster always ran `go build`, whatever the project was — which
in an Odin project produced a Go error about a missing module, and no way to
tell from it that Go was never the point.

What runs now depends on what the project is. A make step in the
configuration wins, because a Makefile that already cross-compiles knows
things this cannot; it is given IDEAI_TARGET_OS, IDEAI_TARGET_ARCH, GOOS and
GOARCH, and the configuration's program is the binary it must produce. Failing
that: Go by its module, Zig by its build.zig, Odin by its sources. Anything
else says so plainly instead of guessing.

Odin needed two steps. Its own linker refuses to make a Linux binary on a
Mac — "linking for cross compilation for this platform is not yet supported" —
but it will emit the objects, and zig ships a linker that takes them. So Odin
emits objects for linux, zig cc links them into a static ELF, and that is
what goes into the pod.

Verified: the odin-hello example built on this machine, pushed into a
development pod, and printed its readings from inside the cluster.
