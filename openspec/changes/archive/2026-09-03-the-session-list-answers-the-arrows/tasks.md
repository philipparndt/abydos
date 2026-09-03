## 1. The selection

- [x] 1.1 A selection in `RunningSessionsListView`: an index into the drawn rows, moved by one and walked past anything that is not a session, kept by id across a reload and falling back to the first row.
- [x] 1.2 Drawn in `selectionBackground`, with the hover tint left as it is, so the two are told apart.
- [x] 1.3 Scrolled into view when it moves.

## 2. The keys

- [x] 2.1 The list takes the keyboard — `acceptsFirstResponder` — and answers ↓, ↑, ⏎ and Escape.
- [x] 2.2 The field answers ↓ by handing the responder to the rows and selecting the first; ↑ from the first row hands it back with the caret at the end.

## 3. Proving it

- [x] 3.1 The driven report says where the keyboard is and which row is selected; a step presses a key in the popover.
- [x] 3.2 Driven: ↓ out of the field selects the first row, ↓ again moves, ↑ twice returns to the field with the filter intact.

## 4. Finishing

- [x] 4.1 Say it in the release notes.
- [x] 4.2 `make test` and `make warnings`, both clean, both by their exit codes. Green here on 2026-09-03: 4017 tests in 512 suites, exit 0, load 30.2 over 14 cores; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `running-sessions` delta in
this change is what it makes true.
