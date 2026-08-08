# Profile and coverage, behind the debug button's chevron

`b8ed4dd8f` · 2026-08-02

Two buttons is the right number for a titlebar: run, and debug. Profiling
and running with coverage are wanted now and then rather than constantly, so
they live behind a chevron beside the ladybird — a click still debugs.

Profile starts the configuration and puts the profiler in front of it: for a
cluster configuration, through a forward to the pod's pprof port; otherwise
at localhost:6060, where a Go service with net/http/pprof serves.

Coverage runs the tests rather than the program — coverage is a property of
a test run — and prints the per-function summary under them. Go only so far,
and it says so for a project without a go.mod rather than failing oddly.
