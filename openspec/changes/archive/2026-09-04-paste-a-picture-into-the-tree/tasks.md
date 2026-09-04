## 1. The board and the name, in AbydosKit

- [x] 1.1 `FilePasteboard.hasPicture(on:)` from `availableType(from: [.png, .tiff])`, reading nothing; `FilePasteboard.picture(on:) -> Data?` returning the board's PNG bytes as they are, or its TIFF decoded through `NSBitmapImageRep` and encoded as PNG, or nil.
- [x] 1.2 Tests in `FilePasteboardTests` against a scratch board: PNG bytes come back unchanged; a TIFF-only board comes back as a PNG of the same size; text is not a picture; a board with a file URL beside pixels still lists the file; bytes the decoder refuses give nil.
- [x] 1.3 `FileTransfer.freeName(stem:extension:in:isTaken:)` beside `duplicateName`, sharing its rule; `duplicateName` expressed through it if that reads better. Tests in `FileTransferTests`: the first picture is `picture-1.png`, a gap is taken before the next count.

## 2. The paste

- [x] 2.1 `paste(_:into:from:)` takes the board, defaulting to `.general`; when `files` is empty and the operation is `.copy`, read `picture`, write it to the free name with `.withoutOverwriting`, record `FileUndo.created`, `pendingReveal`, and reload the parent preserving identity.
- [x] 2.2 The name field: after the reload finds the row, `beginEditing(.rename)` with the stem selected, as `commitName`'s create branch does for its own row. Escape leaves the file.
- [x] 2.3 Not opened: no `onSelectFile` on the paste path, and a comment at the call site saying why, beside `revealExported`'s.
- [x] 2.4 The toast for a picture the decoder refused, and for a write the file system refused, through `Toast.post` as a transfer's failure is.

## 3. The menus

- [x] 3.1 `outline.canPaste` and `menuNeedsUpdate`'s `contextPaste` case: files, or a picture. `contextPasteAsMove` stays files only.
- [x] 3.2 ⌥⌘V by character in `handleKeyDown` unchanged; over a pixels-only board it reaches `paste(.move, …)`, which reads no files and refuses anything but `.copy` for pixels, so it does nothing. By construction rather than driven: the row menu's step reads the general board, which a driven run leaves alone.

## 4. Proving it

- [x] 4.1 The driver step `paste-picture:<path>`: the PNG at the path onto a named board, `paste(.copy, into:, from:)`, and a `TREE paste-picture:` line naming the file and its pixel size.
- [x] 4.2 Driven on a scratch project on 2026-09-03: onto `docs/images` → `docs/images/picture-1.png`, field up with `picture-1` selected; onto `docs/README.md` → `docs/picture-1.png`; `picture-1` and `picture-3` present → `picture-2.png`; Escape keeps the file and the row stays selected; `rename:` over the offer gives `editor-zoomed.png`; the editor keeps `notes.md` in front and Return then opens the picture; ⌘Z through the responder chain removes it; a board declaring PNG over text bytes writes nothing and toasts *Cannot paste that picture*. Capture of the row in its field taken.
- [x] 4.3 Timed in the driven run at load 3 over 10 cores: a 5120×2880 PNG pastes in 0.031 s (bytes written as they are); the same picture as TIFF, decoded and encoded, in 0.135 s. Not worth a thread.

## 5. Finishing

- [x] 5.1 Said in `docs/release-notes-0.13.0.md`, the first section of the next release.
- [x] 5.2 Green on 2026-09-03 by their exit codes: `make test` 4031 tests in 513 suites, exit 0, load 27.9 over 10 cores; `make warnings` exit 0 after the navigator's recorded length in `Scripts/file-size-allowed.txt` was raised from 4239 to 4364 for the picture paste, its name field and the driven step — state the paste needs (`rootNode`, `pendingReveal`, `beginEditing`, `remember`) is the controller's own and private, so a file of its own would have widened all of it.
