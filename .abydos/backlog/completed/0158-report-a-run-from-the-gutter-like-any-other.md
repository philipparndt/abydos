# Report a run from the gutter like any other

`a81cd0154` · 2026-08-02

The arrow beside `func main` started a program and told the titlebar
nothing: no colour, no stop button, no exit code. It went through its own
path, which predates the run strip and never learned about it. Both paths
now share one place that watches the process, so what starts from the
gutter is stoppable and says how it went.

Debugging from the gutter says "Starting…" until the adapter answers,
since the wait before a debugger attaches is long enough to look like
nothing happened.
