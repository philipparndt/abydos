## 1. Listing

- [x] 1.1 `VboardClient.boards(matching:limit:)`: `GET /api/v1/boards?q=&limit=`,
  decoded into `VboardBoardSummary` (id, name, updated), private boards dropped,
  outcomes as the other calls give them.
- [x] 1.2 Tests against the stubbed protocol: the query sent, decoding, private
  boards left out, signed out.

## 2. The pane

- [x] 2.1 `VboardPaneView+Dialogs.swift`: the download, JavaScript dialog and
  open-panel delegates moved out unchanged.
- [x] 2.2 `VboardPaneView` opens a board id: no document, loads `/b/<id>`, no
  lease, nothing ended on close, status says it is the live board.
- [x] 2.3 The tab: `openPage` named `vboard/<host>/<id>`, torn down on close.

## 3. Commands

- [x] 3.1 `VboardBoardPicker`, shaped like `ProcessPicker`: asks the server as
  the text changes, signs in first when the server wants it.
- [x] 3.2 File ▸ Open vboard Board… and File ▸ Save a Copy of the Board….

## 4. Finishing

- [x] 4.1 Tried against a classic `vboard-local` in the scratchpad: list,
  open, edit seen in a browser, close leaves the board, copy saved.
- [x] 4.2 `docs/release-notes-0.23.8.md` gains a `##` for it.
- [x] 4.3 `make test` and `make warnings`, exit codes read.
