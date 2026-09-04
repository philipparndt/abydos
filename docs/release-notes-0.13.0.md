# Abydos 0.13.0

## A picture on the clipboard pastes into the tree

Asked for on 2026-09-03: a screenshot on the clipboard, pasted into the
project tree, as a file. ⌘V in the tree has pasted *files* since item 0436 — a board
that held pixels and no file was, to the tree, an empty board, and Paste stayed
grey over a screenshot taken a second earlier.

Now ⌘V, Edit ▸ Paste and the row menu's *Paste Item* take a board that carries
a picture and no file and write it as a PNG where a pasted file would land:
the selected folder, the folder holding the selected file, or the project root.
A board that already carries PNG bytes is written as it is — the program that
put it there had encoded it once, and `NSImage(pasteboard:)`, the obvious call,
would have re-encoded from a bitmap and could have made it larger. A board with
TIFF alone is decoded and written as PNG, because a `.tiff` in a repository is
a question at review time.

The name is offered, not demanded. The file is written the moment ⌘V arrives,
under the first free `picture-<n>.png`, and the row opens for renaming with the
stem selected: typing replaces it, Escape keeps it. That is not the New File
order, where nothing is on disk until Return, and on purpose — an empty file
Escape left behind is something, but a picture is the thing that was pasted,
and ⌘Z is the answer to a change of mind. *Undo Paste* is what the Edit menu
says, and it moves the file to the trash with the guard every created file
has: one written to since is left alone.

The row is revealed and selected and not opened, on the diagram export's
reasoning: a screenshot is pasted into a project to be referred to from
something being written, and an image tab taking the front would be the paste
stealing that place. Return on the row opens it, as any picture row's does.

Files still come first — a file copied in the Finder can carry pixels beside
its URL, and the file is what was meant — and *Move Item Here* stays a
files-only gesture, since pixels have nowhere to be moved from. Whether Paste
is enabled is read from the board's types, because a menu validates every time
it opens; the bytes are read once, when the key is pressed. A board that
declares a picture and carries rubbish under it writes nothing and says so.

Measured in the driven run at load 3 over 10 cores: a 5120×2880 PNG pastes in
0.031 s, and the same picture as TIFF, decoded and encoded, in 0.135 s. The
run pastes from a board of its own, so proving the gesture never writes the
clipboard of whoever is at the keyboard.

The spec is `pasted-pictures`, new — and the first OpenSpec requirement any of
the tree's file operations have; ⌘C, ⌘V, drop, New File, rename and the
tree's undo stack were built under the old backlog's numbers.
