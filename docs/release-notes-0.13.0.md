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

## A picture pasted into a document is a file and a reference

The follow-up, asked for the same day: ⌘V over a picture in a Markdown or
HTML document writes it as a PNG into `images/` beside the document — made on
first use — and puts a reference at the caret, `![](images/notes-1.png)` or
`<img src="images/notes-1.png" alt="">`, with the caret inside the empty
description so the next thing typed is the alt text. The file is named for
the document, `notes-1.png` for `notes.md`, because a folder shared by every
document beside it otherwise says nothing about which picture is whose.

Text on the board still pastes as text; the picture path is taken only when
there is none. A language with no picture syntax — pixels into a Swift file —
pastes nothing and greys Paste out, since a file written into the source tree
that nothing references is a stray screenshot in the repository. The file is
written first and the reference inserted second, as one edit: ⌘Z in the editor
takes the reference back and leaves the file, which is in the tree, where the
tree's own ⌘Z removes it. Two undo stacks, and focus decides which, as they
were built to.

**The preview had never drawn a picture.** Foundation's Markdown parser turns
`![alt](path)` into the alt text and nothing else, and only diagrams were
being made into attachments — so every screenshot in every README rendered as
its own description, and nobody had said so. A picture in a document is now
the diagram's attachment cell, fitted to the pane, decoded once per version
of the file so typing beside a 5k screenshot does not decode it on every
keystroke.

Measured at load 3 over 10 cores: a 5120×2880 PNG pastes in 0.010 s, the same
picture as TIFF in 0.121 s.

One thing is left open. What a browser's *Copy Image* puts on the board beside
the pixels was not measured — that copy has to be made by hand in somebody's
browser — so text-first is the rule until the table says otherwise: if a
browser puts the image's address on the board as text, ⌘V pastes the address.
