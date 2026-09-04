## Context

`CodeView.paste(_:)` is one line: the board's string, inserted at the caret
through `insertTextAtCaret`, which is one `TextDocument.replace` and so one
undo entry. The view knows its document's `url` and `languageId`. The Markdown
preview is `MarkdownRenderer.render(_:baseURL:)` with the document's folder as
the base. **Corrected during implementation:** the base resolved links only.
Foundation's parser leaves `![alt](path)` as its alt text carrying `imageURL`,
and the renderer made attachments for diagrams alone, so no picture had ever
been drawn in the preview; this change makes image runs into the diagram's
attachment cell, which is what the preview requirement turned out to need.

`paste-a-picture-into-the-tree` put the pasteboard reading in AbydosKit —
`FilePasteboard.hasPicture` asks the board's types, `picture` returns PNG
bytes — and `FileTransfer.freeName` names a file that has none. This change
reuses both and adds only what a document needs: where, what name, what text.

This repository keeps its own pictures in `docs/images/`, referenced from
`docs/index.html` as `images/<name>.png`. That is the convention this design
follows, because it is the one already in front of whoever reads this.

## Goals / Non-Goals

**Goals:**

- ⌘V over a picture in a Markdown or HTML document writes the file beside the
  document and inserts the reference at the caret, with the caret where the
  description goes.
- The name says which document the picture belongs to.
- The Markdown preview shows the picture without anything else being done.
- The arithmetic is in AbydosKit and tested without a window; the gesture is
  proved in a driven run without touching the general clipboard.

**Non-Goals:**

- Pictures in languages with no picture syntax. Pixels into a Swift file do
  nothing, as today.
- Dragging a picture (pixels, not a file) onto the editor.
- Resizing, renaming or moving the picture afterwards. It is a file in the
  tree, and the tree's gestures are its gestures.
- Rewriting references when the document is moved. Nothing in the app rewrites
  references today, and starting with pictures would be starting in the wrong
  place.

## Decisions

### `images/` beside the document

The picture goes into a folder named `images` in the document's own folder,
created if absent. It is where this repository's pictures are, it is what the
`docs/index.html` references read as, and a folder beside the document keeps
the relative path one segment long.

*Ruled out:* a folder per document, `notes/` beside `notes.md`. One document
with one picture makes a folder for it, and a `docs/` with twelve documents
makes twelve. *Ruled out:* the picture beside the document with no folder.
Prose and pictures in one listing is a listing nobody can read after the
tenth screenshot. *Ruled out:* one folder at the project root. The reference
then climbs — `../../images/x.png` — and breaks the first time the document
moves a level.

*Open:* whether an existing `assets/` or `img/` beside the document should be
preferred over making `images/`. The right rule is probably "the folder the
document already references pictures from, else `images/`", and it wants a
look at what the document says before it is written down as a requirement.

### Named for the document

`FileTransfer.freeName(stem: <document stem>, extension: "png")`, so
`notes.md` gets `images/notes-1.png`, then `notes-2.png`, the first number
free. In a folder shared by every document beside it, the name is the only
thing that says which document a picture belongs to.

*Ruled out:* `picture-<n>.png`, the tree's stem. Right there — the tree's
paste has no document to name it after — and wrong here, where twenty
pictures from twelve documents would be twenty numbers.

### The reference, per language

| language | reference | caret |
|---|---|---|
| Markdown | `![](images/notes-1.png)` | between `[` and `]` |
| HTML | `<img src="images/notes-1.png" alt="">` | inside `alt=""` |

The caret lands where the description goes, with nothing selected, so the
next thing typed is the alt text and Return moves on. A table rather than a
switch, so a third language is a row.

*Ruled out:* every other language gets the relative path as text. A ⌘V aimed
at the wrong tab would then write a file into the source tree that nothing
references, and the file is the expensive half of the mistake. Paste over
pixels stays a no-op there, which is what it is today.

*Open:* reStructuredText (`.. image::`), AsciiDoc (`image::[]`) and LaTeX
(`\includegraphics`) each have a syntax and are each a row in the table; none
is written down here because nobody asked, and a row for a language nobody
here writes is a row nobody checks.

### The file first, the reference second, one undo for the text

The picture is written, then the reference is inserted as one `replace`, so
⌘Z in the editor takes the reference back and leaves the file. The file is in
the tree, where ⌘Z over the tree removes it, as `paste-a-picture-into-the-tree`
says. Two stacks, and focus decides which — the rule `NavigatorOutlineView`'s
undo was built on, and the reason a text undo must never delete a file.

*Ruled out:* one undo for both. It would be the first editor undo that touches
the disk beyond the document, and the fright of ⌘Z removing a file is the
fault the two stacks exist to prevent.

*Open:* whether the editor's paste should record the file on the *tree's*
stack as a `.paste` gesture, so that ⌘Z over the tree afterwards removes it
without the tree having seen the gesture. The tree owns that stack; the editor
would need a hook to reach it. Cheap, and probably right, and not decided
here.

### Text first, then the picture

The board's string is pasted when there is one, as today; the picture path is
taken only when there is none. The editor is a text editor and ⌘V over text
has always pasted the text.

*Open, and to be measured rather than reasoned about:* what a browser's *Copy
Image* puts on the board beside the pixels. If it carries the image's address
as `.string`, text-first pastes a URL where a picture was wanted, and the rule
would need to be "a string that is only a URL to the same picture is not
text". `FilePasteboard`'s doc comment is a table of measurements for exactly
this kind of question, and this one wants the same table before a rule.

### `PictureReference`, in AbydosKit

One value: document URL and language in, folder, file URL, reference text and
caret offset out, with `isTaken` injected. Every decision above is a test
against it, and `CodeView` does only what a view must — read the board, write
the bytes, replace the text, place the caret.

## Risks / Trade-offs

- [The document is unsaved and has no folder — a scratch] → the scratch
  directory is its folder, and `images/` goes there; a scratch that is later
  saved elsewhere carries a reference that no longer resolves. Said in the
  toast when the document is a scratch: *pasted beside the scratch*.
- [`images/` cannot be made — a read-only checkout] → the write fails with the
  file system's reason, no reference is inserted, and a toast says so. A
  reference to a file that is not there is worse than no paste.
- [The board holds a picture the decoder refuses] → `picture` returns nil, a
  toast says the clipboard's picture could not be read, nothing is inserted.
- [A large screenshot encoded on the main thread] → once per ⌘V, tens of
  milliseconds; measured in the driven run and said with the load.
- [Menu validation asked often] → `hasPicture` reads types, not bytes, and the
  language check is a dictionary lookup.
