# Talk to language servers: diagnostics, go to definition, hover

`f0a200fc6` · 2026-08-01

A client for the language server protocol, and the wiring that puts what a
server says on the screen. Problems are underlined where they are, with the
message in the tooltip; ⌘-click follows a symbol to where it is defined.

One server per language per project, started when the first file of that
language is opened and kept until the project closes — they are slow to
start and spend their first minute indexing, so a server per file would mean
never getting an answer. Nothing waits on one: a server that is missing,
slow or broken costs the features it provides and nothing else. Requests
carry a deadline for the same reason.

No server is bundled and none is installed on anybody's behalf. The one
already on the machine matches the toolchain actually being used, which is
the one that gives correct answers; where it is missing, the registry knows
the single sentence that says how to get it. A GUI app inherits almost none
of a login shell's PATH, so the places these tools actually live are
searched explicitly — without that everything works from a terminal and
nothing works from the Dock. A server is only started for a project it
understands, so a stray .py file does not summon a Python server.

Documents are synchronised whole rather than incrementally. Incremental is
less traffic but has to be exactly right, and when it is not the server's
copy silently drifts from the file and every answer after that is about a
place that no longer exists.

Tested against sourcekit-lsp where it is installed, including real
diagnostics for a file that does not parse — the only way to know the client
speaks the protocol rather than merely parsing what it expects to be sent.
