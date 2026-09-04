## 1. The arithmetic, in AbydosKit

- [x] 1.1 `PictureReference`: document URL and language in; the `images` folder beside the document, the file URL from `FileTransfer.freeName(stem: <document stem>, extension: "png")`, the reference text and the caret offset within it — a table of languages (`markdown`, `html`) rather than a switch. Nil for a language not in the table.
- [x] 1.2 Tests, named as claims: a Markdown document gets `![](images/notes-1.png)` with the caret at 2; HTML gets the `img` tag with the caret inside `alt`; a second picture is `notes-2`; two documents in one folder do not share names; Swift gets nil; the path is relative to the document.
- [ ] 1.3 Measure what a browser's *Copy Image* puts on the board beside the pixels, and write the table into `FilePasteboard`'s doc comment beside the existing one. Decide text-first from the table, and update `design.md` from *open* to decided. **Not done on 2026-09-04**: the measurement needs a browser copy made by hand, which a driven run cannot make and an agent must not make in somebody's browser. Text-first is shipped as the rule until the table says otherwise.

## 2. The paste

- [x] 2.1 `CodeView.paste(_:)`: the string when there is one; otherwise `FilePasteboard.picture()` and `PictureReference` for the document — write the bytes with `.withoutOverwriting`, making `images` first, then one `replace` for the reference and the caret placed inside it.
- [x] 2.2 `validateUserInterfaceItem` for `paste:`: enabled over text, or over a picture when the document's language is in the table.
- [x] 2.3 The toasts: a picture that would not decode; a folder or file that would not write. Nothing inserted in either case.
- [x] 2.4 The scratch case: a scratch's directory is its folder; the toast says *pasted beside the scratch*. By construction — `ScratchFiles.isScratch` after the write — and not driven, since a driven run does not open a scratch.
- [x] 2.5 Found on the way: the Markdown preview never drew a picture at all — Foundation's parser leaves `![alt](path)` as its alt text carrying `imageURL`, and only diagrams became attachments — so the spec's preview requirement was unmet for every picture, not only pasted ones. `MarkdownRenderer` now turns an image run into the diagram's attachment cell, fitted to the pane, decoded once per version of the file.

## 3. Proving it

- [x] 3.1 The editor's `paste-picture:<path>` driver step, from a named board; an `EDITOR paste-picture:` line naming the file and `lineTextForTesting` of the caret's line.
- [x] 3.2 Driven on 2026-09-04: `notes.md` gets `images/notes-1.png` and `![](images/notes-1.png)` with the caret at 2; typing gives `![the editor zoomed](…)`; ⌘Z takes the alt text, a second ⌘Z the reference, and the file is still on disk; `index.html` gets the `img` tag with the caret inside `alt`; `readme.md` beside `notes.md` gets `readme-1.png`; a second paste is `notes-2.png`. Capture of the preview showing the picture taken. A 5120×2880 PNG pastes in 0.010 s and the same as TIFF in 0.121 s, at load 3 over 10 cores.
- [x] 3.3 Driven: pixels into `main.swift` — nothing written, the line unchanged, no `images` folder.

## 4. Finishing

- [x] 4.1 Said in `docs/release-notes-0.13.0.md`, beside the tree's paste.
- [x] 4.2 Green on 2026-09-04 by their exit codes: `make test` 4038 tests in 514 suites, exit 0, load 25.4 over 10 cores; `make warnings` exit 0 after `Scripts/file-size-allowed.txt` was raised for `CodeView.swift` (4513 → 4585, the picture paste and its validation, which need the view's private caret and selection) and `EditorViewController.swift` (4948 → 4976, the driven step, which needs `codeViewToDrive`).
