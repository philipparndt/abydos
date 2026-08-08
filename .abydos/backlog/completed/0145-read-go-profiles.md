# Read Go profiles

`fc4ac1e06` · 2026-08-01

The first half of the profiler, with no UI on it yet: a pprof decoder, a
flame graph model, and a client for a program's /debug/pprof endpoint.

The decoder is a few hundred lines of wire format rather than a vendored
protobuf toolchain, for one message type whose shape has been stable for
a decade — and it steps over fields it does not know, so a profile from a
newer Go stays readable. Verified against profiles Go actually writes,
both from a file and from a running program.
