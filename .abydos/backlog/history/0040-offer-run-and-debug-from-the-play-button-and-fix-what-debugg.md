# Offer run and debug from the play button, and fix what debugging needed

`fd7859c01` · 2026-07-31

The play button now opens a menu rather than starting a process on a
single click — run and debug are both things you want from the same
marker. The pointer becomes a hand over it, since it is the only part of
the gutter that reads as a control.

Several things behind it were wrong:

- The Go menu commands still refused to do anything unless go.mod sat at
  the project root. They now find the module below it, ask only when
  there is genuinely more than one, and run there — `go test ./...` from
  a directory with no go.mod fails whatever the arguments say.

- Delve builds with `go build`, which also only works inside the module,
  so the debugger runs from the package's own directory rather than the
  project root.

- `dlv dap` is a TCP server, not a stdio adapter: writing to its stdin
  reached nothing at all, which is why debugging had never worked. The
  client speaks over a socket now, starting the adapter on its own port
  and connecting to it — the mode VS Code uses. Its `--client-addr`
  alternative, where the adapter dials back, was tried first and stalls
  after the build.

- The adapter inherits a PATH with the usual toolchain locations. A GUI
  app's PATH has none of them, and Delve shells out to `go`.

- `canonicalPath` used Foundation's `resolvingSymlinksInPath`, which has
  a special case that rewrites a leading `/private` *back* to `/tmp` —
  the opposite of resolving. Two paths compared with it still matched,
  so the editor's own bookkeeping worked, but handing the result to `go`
  produced a package path outside the module and the build failed. It
  uses realpath(3) now.

- The ⌃R menu was popped up at a screen point that had already been
  converted from screen coordinates, so it appeared off the window.
