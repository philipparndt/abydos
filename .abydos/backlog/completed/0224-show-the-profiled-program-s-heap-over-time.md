# Show the profiled program's heap over time

`a6278232d` · 2026-08-03

A profile says where the memory went at one moment; it cannot say whether
the heap is growing, which is the question people start with. So the
profiler pane now watches the program it is pointed at and draws a line:
heap now, the peak, what it has put on since connecting, and every byte
allocated since the program itself started.

The numbers come from `expvar` at /debug/vars where the program has it,
and from the MemStats footer of a text heap profile where it has not —
which is most programs, since pprof is an import away and expvar is a
second one. The strip appears only once a reading has arrived, so a
program that offers neither shows a flame graph and nothing else.
