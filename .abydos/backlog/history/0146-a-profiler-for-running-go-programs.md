# A profiler for running Go programs

`717606185` · 2026-08-01

Point it at a program's pprof endpoint and look at where the time or the
memory went: a flame graph for shape, a table for numbers, and a click on
a frame to search the project for that function. Nothing is installed
into the program under study — it already serves all of this.

The flame graph zooms into a frame on click and back out on escape,
which is the only way to read the narrow end of a real profile. Frames
take their colour from their name, so one function is one colour
wherever it appears.
