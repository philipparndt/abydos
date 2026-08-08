# Add Go run, build, test, trace, profile and debug

`2d7dc986b` · 2026-07-30

Run menu commands for Go projects, executed in the panel so output is live and
interactive rather than captured and dumped at the end.

Finding the toolchain is the awkward part: a GUI app inherits no login shell, so
PATH usually lacks both Homebrew and /usr/local/go/bin. The known locations are
checked directly rather than hoping the environment is right — the same reason
the login shell is started with -l.

Run, build and debug need a specific main package, so main packages are
discovered by reading package clauses (ignoring mentions inside comments) and
the user is asked only when a module contains more than one. Vendored code is
skipped: it is a dependency, not something this project runs.

Trace and profile chain two commands through a shell, because `go tool trace`
and `pprof` consume the file the first command produces.

Debugging runs Delve's own terminal UI rather than a native panel. Delve is
fully featured today and the terminal hosts it properly; a native front end
would need a DAP client plus its own breakpoint, stack and variable views, which
is a much larger piece of work and is noted as such.

159 tests.
