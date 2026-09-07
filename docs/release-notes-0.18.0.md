# Abydos 0.18.0

## Blame is where the file is, and lands on the commit

Blame was only in the editor's gutter menu and on ⌥⌘B, and a colleague
looking for it in the tree and on the tab did not find it. Now *Blame* is on
the file's row in the project tree and on the tab's menu, and the palette
offers *Toggle Blame* by name. From the tree and the tab it opens the file if
it is not open and turns the column on.

Clicking a blame entry used to put the hash in a toast. Now it opens the log
page scoped to the file at that commit, with the commit's row selected, so the
message and the diff of the file are on screen. A line that is not committed
yet says so, in a toast.

The column follows a line through a move and a copy, so a block one author
moved keeps the author who wrote it, and a `.git-blame-ignore-revs` file at
the root keeps a formatting commit from owning every line it touched.
