## 1. The mark

- [x] 1.1 Draw the dot in `NavigatorCellView`, in `Theme.color(for:)` of the node's state, for every state but `unmodified` and `ignored`.
- [x] 1.2 Off both, and against `markEdge` rather than the cell's width — the first version measured the name against one edge and drew the mark at another, which agree until the pane is narrow. Reported, fixed, captured at 250 points with a name long enough to truncate.

## 2. Proving it

- [x] 2.1 Driven capture over a scratch repository, and it is what found the mark being drawn off screen — the tree's column is sized to its widest row and the root carries the project's whole path, so a cell is routinely wider than the pane. The first capture had no dots in it at all. Pinned to the visible edge, the second has them: orange on the untracked file, blue on the modified one, nothing on the clean one, and the roll-up on the folder above.

## 3. Finishing

- [x] 3.1 `make test` and `make warnings`, both clean, both by their exit codes. Green on the reporter's machine, 2026-09-02: 4004 tests in 511 suites passed after 81.4 s with 2 known issues, exit 0. Every run here the same afternoon was red on one load-bound give-up test at loads of 16 to 56 over 14 cores.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
