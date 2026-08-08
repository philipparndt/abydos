# A language server is given a PATH with a compiler on it

`9ebd4dfe2` · 2026-08-05

gopls started, answered the handshake, published a diagnostic — and knew
nothing about any symbol in the project. What it said was "No active builds
contain app/main.go", which reads as a fact about the project, so go-to-
declaration looked like a language server that had not started yet and never
would.

It had started. It could not run `go`. A server inherits this app's
environment, and an app launched from the Dock has /usr/bin:/bin and the two
sbins — the compiler every language server shells out to is in Homebrew's
directory or the toolchain's, neither of which is there. Driving gopls by hand
with that PATH reproduces the screenshot exactly:

  Error loading packages: err: go command required, not found:
  exec: "go": executable file not found in $PATH
  No active builds contain .../app/main.go

The same directories the server itself was found in now go on its PATH, after
whatever was inherited, so a PATH somebody set deliberately still chooses the
toolchain. The debug adapter has done this for dlv since it was written; the
language servers never got it.

Two more things were wrong, and they are why this took a screenshot to find
rather than a glance:

Nothing was written down. ~/Library/Logs/ideai/lsp.log now takes every
lifetime event — which server started where and from which binary, the
handshake, everything the server says about itself, its standard error (read
and dropped on the floor until now), and every question that failed or was
asked when no server was running. On the event rather than behind a switch: a
log that has to be turned on is off when it is wanted. It rotates at a
megabyte, and the tmux trace shares it.

Nothing was said. An error from a server — level 1, the protocol's word for "I
am not going to answer anything" — now raises a toast with the server's own
sentence in it, once per server rather than once per file, since one that
cannot load a workspace repeats itself for every file opened afterwards. A
server that is merely not installed is logged and not announced; half the
projects on a machine touch a language nobody installed a server for.

And two gaps that made the announcement worthless: a toast was shown only by
the key window, so anything raised while the app was in the background went
nowhere — which is exactly where the app is during the seconds a server takes
to fail. The frontmost window says it when none is key, still exactly one of
them. And the symbol palette's "or the language server is still starting" now
gives way to what the server actually said, when it has said something.
