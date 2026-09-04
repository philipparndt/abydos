## Why

A screenshot on the clipboard, pasted into a Markdown document, does nothing:
`CodeView.paste(_:)` reads `string(forType: .string)` and a board holding
pixels has none, so ⌘V is a key that was heard and not answered. What somebody
writing documentation wants is the picture *in the document* — a file beside
it and a reference at the caret, which is what every wiki, chat and notebook
does with the same key. Today it is: paste into the tree (once
`paste-a-picture-into-the-tree` lands), find the file, work out the relative
path, type the reference by hand.

Asked for on 2026-09-03, as the follow-up that change's design left out in so
many words: "Pasting a picture into an editor or a Markdown document, and
writing the reference. That is the editor's subject, and the file this change
makes is what such a feature would refer to."

There is no originating `.abydos/backlog` item. This follows
`paste-a-picture-into-the-tree`, and reuses what it made in AbydosKit.

## What Changes

- **A picture pasted into a Markdown or HTML document becomes a file and a
  reference.** ⌘V over a board that holds an image and no text writes the
  picture as a PNG into `images/` beside the document — made if it is not
  there — and inserts a reference to it at the caret: `![](images/notes-1.png)`
  in Markdown, `<img src="images/notes-1.png" alt="">` in HTML. The caret
  lands where the description goes, so the next thing typed is the alt text.
- **The file is named for the document.** `notes.md` gets `notes-1.png`, then
  `notes-2.png`, the first number free — so a shared `images/` folder says
  which document each picture belongs to.
- **The preview shows it at once.** The Markdown preview resolves relative
  paths against the document, so the picture appears in the rendered half as
  the reference is typed.
- **Text still comes first.** A board with text pastes the text, as it always
  has; the picture path is taken only when there is no text to paste. A board
  with a file URL pastes its path as text, as it does today.
- **Other languages are unchanged.** Pixels pasted into a Swift file do
  nothing, as today: a paste that wrote a file into the source tree which
  nothing references would be a stray screenshot in the repository.
- **The editor's undo is the text's.** ⌘Z takes the reference back and leaves
  the file, which the tree can remove; the two stacks stay apart, as they were
  built to.

## Capabilities

### New Capabilities

- `pasted-pictures-in-documents`: what a picture on the clipboard becomes
  when pasted into a document — where the file goes, what it is called, what
  the reference looks like per language, where the caret lands, what the
  preview shows, and what undo does.

### Modified Capabilities

None. `pasted-pictures` is the tree's paste and is unchanged; `previews`
already says a Markdown document renders beside its source; `editor`'s
requirements about keys and the caret are not touched.

## Impact

- **AbydosKit**: `FilePasteboard.hasPicture`/`picture` and
  `FileTransfer.freeName` are reused as they are. New: `PictureReference`,
  the arithmetic — given a document URL and a language, the folder the
  picture goes in, the file's name, the reference text and where the caret
  goes in it — tested without a window.
- **AbydosApp**: `CodeView.paste(_:)` takes the picture path when there is no
  string; `validateUserInterfaceItem` for `paste:` enables over a picture in
  a document that has a syntax for one. The write happens before the insert.
- **Driver**: a `paste-picture:<path>` step for the editor, from a named board,
  reporting the file written and the line it was written into.
- **Cost**: one board read, at most one PNG encode, one file write, one text
  replace — per ⌘V, and nothing per keystroke.
