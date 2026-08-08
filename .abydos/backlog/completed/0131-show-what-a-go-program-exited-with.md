# Show what a Go program exited with

`aaf6a715f` · 2026-08-01

Delve sends no exit event and no code with `terminated`; it only says how
the program went when asked to disconnect, which is where VS Code reads
it from too. Asking costs nothing — the session is over either way — and
the status arrives after the state did, so it is published again.
