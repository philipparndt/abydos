# Stage changes and commit them, in the shape Fork uses

`54875e455` · 2026-07-31

The commit button in the tool strip was a disabled placeholder. It now
opens a staging view in the sidebar: unstaged above, staged below, the
commit message under both, and the selected change's diff as an editor
tab.

Two lists rather than one with checkboxes. The index is a real thing
with its own contents, and a file that was edited, staged, and edited
again is in both states at once — a single list with a tick per row
cannot say that, and a commit built from it would not contain what it
appeared to.

The existing GitRepository collapses a path's two porcelain codes into
the one status the navigator colours rows with, so staging gets its own
reader that keeps them apart. Conflicts are one unresolved entry rather
than a staged change with an unstaged one beside it — offering to stage
half of a conflict would be wrong.

Details that would otherwise lose work: staging uses `add -A` so a
deletion is staged as a deletion instead of being skipped; unstaging
falls back from `restore --staged` to `reset`, which is what works
before the first commit; and the commit message goes in as one -m per
paragraph rather than an embedded newline. Untracked files are diffed
against /dev/null, since git otherwise prints nothing for them.

The lists follow the work tree through the navigator's existing file
system watcher, so editing a file in the editor updates what is
stageable without a manual refresh.
