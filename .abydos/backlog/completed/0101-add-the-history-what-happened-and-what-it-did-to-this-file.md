# Add the history: what happened, and what it did to this file

`e862f8dd1` · 2026-08-01

⌘6, beside the other git tools. Commits at the top, what the selected one
touched underneath, and clicking a file opens that commit's diff for it —
which is the question a log is nearly always being asked. Not "what
happened" but "what happened to this".

So the pane can narrow itself to whichever file the editor has in front,
following it through renames, and widen back to the repository. Branch and
tag names are shown where they point, since that is how a commit is found by
eye. Merges say so: their diff is against the first parent, and reads
differently from an ordinary commit's.

The log is read a page at a time as it is scrolled, so a repository with
forty thousand commits opens as fast as one with four. Searching is git's
`--grep` rather than a filter over what is loaded, which would only ever
find the page you were already looking at. Records come back separated by
control characters: a commit message can contain anything, including
whatever was going to be used as a delimiter.

A commit's diff is read-only — it has already happened, and offering to
stage part of it would be a lie.
