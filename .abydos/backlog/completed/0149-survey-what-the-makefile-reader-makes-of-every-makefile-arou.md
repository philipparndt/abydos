# Survey what the Makefile reader makes of every Makefile around

`3e69af8c1` · 2026-08-01

Opt-in, and it asserts nothing: it prints what the parser and the planner
produce for every Makefile under ~/dev, so "does this work generally or
only for the one file it was written against" is answered by measurement.
Sixty files, all parsed, forty-eight debuggable goals across twenty-three
projects — and the ones that produce nothing are Swift or C projects with
no Go program to start.
