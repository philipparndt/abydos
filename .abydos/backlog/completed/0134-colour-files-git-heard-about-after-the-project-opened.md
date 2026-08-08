# Colour files git heard about after the project opened

`73441b7ca` · 2026-08-01

Two reasons a file was drawn as though it were tracked and unmodified.
The status cache was read once at load, so anything written since — a
build's output, or the binary a debugger leaves behind — had no status
at all; it is re-read now, one `git status` at a time with at most one
queued behind it. And rows whose children load lazily arrived after the
last refresh, so loading them asks for another.

The repository also reported the real path where the tree holds the
standardized one, and under /tmp or the system temporary directory those
differ — every file in such a project failed to match its own repository.
