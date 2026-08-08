# The commit button says there is something to commit

`4c1873bf8` · 2026-08-03

Four small things about the sidebar.

The commit button is tinted when the working copy has changes in it, and its
tooltip says how many. The count comes from the tree's own `git status`,
which it reads on every watcher event anyway — nothing new is run for it.

"Follow the terminal's project" is a setting now, so a window that should
start linked does, instead of being switched on by hand every time. It stays
a per-window switch afterwards: one window following a terminal about while
another stays where it was put is a reasonable way to work.

A tool that cannot be built yet no longer takes the sidebar down with it. The
panes that need a repository were guarded — but the guard ran after the old
view had been removed, so asking for the commit pane while the repository was
still being read left the sidebar blank until somebody thought to close and
reopen it. The view is built first now, and if it cannot be, the ask waits
for the read to finish.

And a sidebar dragged shut until there is nothing left of it counts as
collapsed. It was only "hidden" that counted, so pressing ⌘2 on a sidebar
somebody had dragged closed did nothing at all — twice, since it thought it
was already showing what was asked for.

The row text rules the branches list got are shared now, and the commit list
uses them: a long file name gives way before the directory does, since two
files with the same name are told apart by the directory.
