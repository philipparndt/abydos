# Abydos 0.18.0

## Blame is on the tree, the tab and the palette

*Blame* is on a file's row in the project tree, on the tab's menu and in the
palette as *Toggle Blame*, beside the gutter menu and ⌥⌘B. Clicking a blame
entry opens the log scoped to the file at that commit, with the commit
selected, instead of putting the hash in a toast. Hovering an entry lights its
commit's lines and shows the summary, author, date and hash. The gutter menu
opens on a right-click anywhere in the gutter. The column follows lines
through moves and copies, and honours `.git-blame-ignore-revs`.
