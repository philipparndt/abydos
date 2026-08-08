# Add new files from the tree, and scratch files per project

`3ddd0d340` · 2026-08-01

Two ways to get a file that does not exist yet.

"New File…" sits above "New Folder" in the tree's context menu and takes
the same path: a name with slashes in it makes the directories on the way,
and the file opens once it is there. The name check that folders already
had is now shared, so a file called `.` or `a/../b` is refused with the
same words.

A scratch is for something that is not part of the project — a query, a
paste, a snippet worth keeping until it is not. Double-click the empty part
of the tab strip (or ⇧⌘N) and one appears, called "Scratch 1" because it
has no name of its own and does not need one. It is a real file, so it
highlights and searches like anything else, but it lives under Application
Support keyed by the project rather than inside it: a scratch has no
business showing up in `git status` or in somebody's commit.

They come back when the project opens again, which is the point — nothing
else holds what is in them. Closing an empty one throws it away, so a
stray double-click does not haunt every later launch.
