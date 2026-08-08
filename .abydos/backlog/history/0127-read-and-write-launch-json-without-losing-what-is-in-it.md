# Read and write launch.json without losing what is in it

`84cc51f8c` · 2026-08-01

VS Code's format rather than one of our own: a project usually already has
this file, and the people you share it with expect it to keep working.

The existing reader was Go-only and one-way — it flattened each entry into a
command line, so nothing could be written back. This model round-trips.
Keys it does not know about are carried through untouched, so editing the
arguments of one configuration cannot quietly delete the `buildFlags` or
`showLog` some other tool relies on. Variables like ${workspaceFolder} are
expanded when something is run and kept unexpanded when the file is written,
so it stays portable.

A project with no file at all gets a suggestion built from what is actually
there — the module, wherever it sits — so pressing play can run the obvious
thing and leave a record of what it did, rather than asking a question
nobody has the information to answer yet.
