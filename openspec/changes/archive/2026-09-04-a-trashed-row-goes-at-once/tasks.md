## 1. The rule, in AbydosKit

- [x] 1.1 `DoomedRows`: a set of URLs; `hides(_:)`, `mark(_:)`, `clear(_:)`, and `parents(of:)` for the folders to re-read. Tests as sentences: a marked row is hidden and its siblings are not; clearing two of three leaves one; the parents of three files in two folders are two folders.

## 2. The trash

- [x] 2.1 `trash(_:)`: drop URLs that no longer exist; when nothing is left, reload their parents and return without calling `recycle`.
- [x] 2.2 Mark the rest doomed, reload, then call `recycle`. `rows(under:)` leaves doomed nodes out.
- [x] 2.3 The completion: clear the moved URLs, re-read their parents, reload; the refused ones are cleared too so their rows come back beside the toast; `remember(FileUndo.trashed(moved))` unchanged.
- [x] 2.4 `trashSelection`'s survivor: still worked out before the mark, and honoured by the immediate reload rather than the watcher's.

## 3. Proving it

- [x] 3.1 Driven on a scratch project: `cmd-delete,rows` shows the row gone with no settle; `settle,ls:src` the file gone; `undo-key,settle,rows,ls:src` both back. A collapsed folder the same way.
- [x] 3.2 Driven: a row whose file `rm` removed, then `cmd-delete,toasts` — no toast, row gone.
- [x] 3.3 Say the trash's own time with the load beside it: the interval between the key and the completion.

## 4. Finishing

- [x] 4.1 Say it in the release notes.
- [x] 4.2 `make test` and `make warnings`, both clean, both by their exit codes, with the load said. 4061 tests in 517 suites passed with the suite's two known issues, at load 26.1 over 14 cores; `make warnings` clean.
