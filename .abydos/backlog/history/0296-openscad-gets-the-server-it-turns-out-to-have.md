# OpenSCAD gets the server it turns out to have

`6a192aa83` · 2026-08-05

openscad-lsp exists, is maintained, and answers everything this editor asks:
completion, hover with the documentation comment above a module, jump to
definition, and document symbols — which matters most here, because the
OpenSCAD grammar ships no tags query and ⇧⌘O over a model listed nothing at
all before this.

  cargo install openscad-lsp

The one thing worth writing down is `--stdio`. It listens on a TCP port by
default, and without the flag it starts, waits on 127.0.0.1:3245 for a client
that never arrives, and the editor waits for a handshake that never comes.
Nothing about that failure looks like a missing flag, so the live test asserts
the flag is there as well as exercising the server.

No root markers: OpenSCAD has no manifest, so anywhere a `.scad` is opened is
somewhere it can answer.

Verified against the real server and through the app: the outline of the
examples' bracket model comes back with its variables and modules, and asking
the palette for "bracket" matches `module bracket` and opens it.
