# Find projects on disk in the switcher, ranked by last change

`118de4d33` · 2026-07-31

The switcher listed only projects that had already been opened here,
which makes it useless for the case it exists for — opening a project
for the first time. It now also scans for checkouts, the way tmuxctl
finds them, under an "All Projects" section and in the filter results.

The scan follows the same rules: walk the configured dev directories to
a depth limit, treat any directory holding a .git as a checkout and do
not descend into it, and skip hidden and dependency directories. A .git
file counts as well as a directory, so worktrees are found.

Ranked by when each checkout was last worked on, taken from the mtimes
of the git metadata that changes on commits, checkouts, staging and even
`git status`. That is a stat per candidate rather than a `git` process,
which matters at the ~150 checkouts this finds under ~/dev.

Ties — checkouts whose metadata cannot be read all report the same
distant past — fall back to shallower paths, then path order, so the
list does not reshuffle between scans.

The scan runs off the main thread and is cached across popover opens, so
the list never waits on the file system to appear.

Search paths and depth are settings, defaulting to ~/dev at depth 3.
