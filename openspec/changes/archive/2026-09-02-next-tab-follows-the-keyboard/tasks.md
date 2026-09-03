## 1. The keys

- [x] 1.1 `PanelTabStrip.selectNeighbour(offset:)`: the neighbouring index, wrapping, through the same `onSelect` a click uses.
- [x] 1.2 `BottomPanel.selectNeighbouringTab(offset:)`: the focused column's top strip, or its tmux strip when the top one holds a single tab over it.
- [x] 1.3 `MainWindowController.selectNextTab` and `selectPreviousTab` ask `isTerminalFocused` and go to the panel or the editor.

## 2. Proving it

- [x] 2.1 `--next-tab-in-panel`: with the keyboard in the panel, ⌘⇧] then ⌘⇧[ and what the strip showed each time; then the same with the keyboard in the editor and the strip unchanged. Raise the two recorded lengths for it.
- [x] 2.2 Driven with three terminal tabs: the report shows the strip moving forward, back, and standing still with the editor focused.

## 3. Finishing

- [x] 3.1 Say it in the release notes.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes. Green on the reporter's machine, 2026-09-02: 4004 tests in 511 suites passed after 81.4 s with 2 known issues, exit 0. Every run here the same afternoon was red on one load-bound give-up test at loads of 16 to 56 over 14 cores.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` and `tab-overflow`
deltas in this change are what it makes true.
