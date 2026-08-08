# Work out which project a directory belongs to

`e3abdab31` · 2026-08-01

The first piece of following a terminal: a shell that changes directory has
moved to another project, and this is the question of which one.

The nearest enclosing repository, with one rule that matters. A submodule is
part of the project that contains it rather than a project of its own — you
step into one to change something about the project you were already in, and
a window that followed you there would put away the very thing you were
working on. Its `.git` is a file pointing into the containing repository's
modules directory, which is how it is told apart from a linked worktree,
whose `.git` file points into worktrees and which really is somewhere else to
work.

Filesystem only, no git process: this runs every time the shell moves.
