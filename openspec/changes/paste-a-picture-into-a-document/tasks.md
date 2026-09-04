## 1. The arithmetic, in AbydosKit

- [ ] 1.1 `PictureReference`: document URL and language in; the `images` folder beside the document, the file URL from `FileTransfer.freeName(stem: <document stem>, extension: "png")`, the reference text and the caret offset within it — a table of languages (`markdown`, `html`) rather than a switch. Nil for a language not in the table.
- [ ] 1.2 Tests, named as claims: a Markdown document gets `![](images/notes-1.png)` with the caret at 2; HTML gets the `img` tag with the caret inside `alt`; a second picture is `notes-2`; two documents in one folder do not share names; Swift gets nil; the path is relative to the document.
- [ ] 1.3 Measure what a browser's *Copy Image* puts on the board beside the pixels, and write the table into `FilePasteboard`'s doc comment beside the existing one. Decide text-first from the table, and update `design.md` from *open* to decided.

## 2. The paste

- [ ] 2.1 `CodeView.paste(_:)`: the string when there is one; otherwise `FilePasteboard.picture()` and `PictureReference` for the document — write the bytes with `.withoutOverwriting`, making `images` first, then one `replace` for the reference and the caret placed inside it.
- [ ] 2.2 `validateUserInterfaceItem` for `paste:`: enabled over text, or over a picture when the document's language is in the table.
- [ ] 2.3 The toasts: a picture that would not decode; a folder or file that would not write. Nothing inserted in either case.
- [ ] 2.4 The scratch case: a scratch's directory is its folder; the toast says *pasted beside the scratch*.

## 3. Proving it

- [ ] 3.1 The editor's `paste-picture:<path>` driver step, from a named board; an `EDITOR paste-picture:` line naming the file and `lineTextForTesting` of the caret's line.
- [ ] 3.2 Driven on a scratch project: paste into `notes.md`, type the alt text, paste a second, undo the second in the editor and show the file still there; a capture of the split with the preview showing the picture.
- [ ] 3.3 Driven: pixels into a Swift file leave the file unchanged and write nothing.

## 4. Finishing

- [ ] 4.1 Say it in the release notes, beside the tree's paste.
- [ ] 4.2 `make test` and `make warnings`, both clean, both by their exit codes, with the load said.
