## 1. The gutter menu (AbydosApp)

- [x] 1.1 `CodeView.menu(for:)` branches on the click falling in the gutter (scroll-adjusted `gutterWidth`, the same boundary every gutter click uses) and builds the gutter menu there; the text menu path is untouched
- [x] 1.2 The blame entry: Show Blame / Hide Blame from `isBlameVisible`, action `MainWindowController.toggleBlame(_:)` with nil target so the responder chain lands on the one implementation all handles share

## 2. Proving it

- [x] 2.1 A driven report of the gutter menu (the editor menu report's pattern) on both sides of the boundary: gutter shows the blame entry, text shows the unchanged text menu
- [x] 2.2 Drive the flip: Show Blame, report the title now reads Hide Blame, and the blame column is on (the existing blame driving says so)

## 3. Before finishing

- [x] 3.1 `make test` green (3949 tests, 2 known issues) at load 11–23; `make warnings` clean; the four grown files re-recorded
- [x] 3.2 No `.abydos/backlog/spec/*.md` file is made untrue: blame was unrecorded, and the added requirement is its first account
