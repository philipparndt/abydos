# Drag files from the tree onto the terminal

`fc3b7931e` · 2026-07-31

The tree was not a drag source at all, so nothing could be dragged out of
it — into the terminal or into any other app. It now vends the file's URL,
copy-only in both directions, since dragging a file out of a project should
never be a way to lose it from the project.

The terminal takes those URLs and types them as paths. Going through the
PTY rather than any command-line parsing of our own means it works the same
at a shell prompt and inside an agent's prompt, which is the case this is
for. Paths are quoted only when a shell would otherwise read them as
syntax: most are ordinary, and a prompt full of quotes is harder to edit
afterwards, which is usually what happens next to a dropped path.
