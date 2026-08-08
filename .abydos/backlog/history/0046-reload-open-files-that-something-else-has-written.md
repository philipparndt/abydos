# Reload open files that something else has written

`a66bb4a55` · 2026-07-31

An agent editing a file while it is open left the editor holding the old
text, so the next keystroke — and the save that followed — wrote the
agent's work away. Open files are now re-read when the file system
watcher reports a change and when the window becomes key, so a later
edit builds on top of what the agent did rather than replacing it.

Position is restored as a line and column, not a character offset. An
offset into the old text names a different place in the new one, so an
edit above the caret would silently move it. Line and column survive
changes elsewhere in the file, which is the ordinary case. Scroll
position and collapsed folds are kept too — the folds by line, since the
regions are recomputed by the new parse.

Change detection uses size as well as modification date: an agent that
rewrites a file twice within one second is not unusual, and a date alone
calls the second write unchanged.

Two things are deliberately left alone. A file with unsaved local edits
is not reloaded — replacing it would discard work the user has not seen
saved, and the versions cannot be merged without asking; auto-save keeps
that window short. And a deleted file is not treated as a change, since
reloading would replace the buffer with nothing.
