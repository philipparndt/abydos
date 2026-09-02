## 1. Name the cause before writing anything

- [x] 1.1 Found by reading rather than by driving: `ChangesPane.fill` answers an untracked directory's listing with `outline.reloadData()`, which clears the selection, and nothing puts it back. A driven run still owes the *proof* — see 3.1 — but the mechanism is named and the code is quoted in the design.
- [x] 1.2 Written into the design, and the compaction hypothesis recorded as wrong rather than replaced quietly.

## 2. The behaviour

- [x] 2.1 Add the tree behaviour to `Controls/`: holding a selection across a rebuild, restoring it, and the fallback when the row has gone.
- [x] 2.2 Make a failed restore fall back to the nearest surviving row through `TreeSelection.surviving`, and log that it missed.
- [x] 2.3 Settle the row-identity question from 1.2 and put whatever arithmetic it needs in AbydosKit beside `TreeSelection`, with tests.

## 2b. The two reports that arrived after the proposal

- [x] 2b.1 Apply the fallback the pane already computes when staging takes the selected row away, so the neighbour is selected.
- [x] 2b.2 Give the changes tree a row view that draws the app's selection through `Theme.selection`, the way `NavigatorRowView` does, instead of leaving AppKit to paint its band.
- [x] 2b.3 Check the other three trees draw the app's selection too, and say in the design which of the four did not.
- [x] 2b.4 Make the log page's detail file list take the keyboard when it is clicked into, so the arrows stop going to the commit list above it.
- [ ] 2b.5 Check the same for the other three trees: click a row, then press ↓, and say which trees did not already move.
- [x] 2b.6 Staging took three passes: the async `reloadData`, then the fallback recorded at two of three call sites, then the real cause — `isRestoring` cleared synchronously while `NSTableView` posts its selection change a turn later, so the pane's own restore read as a click and deselected the other list. Written up in the design.
- [x] 2b.8 And the case above has a case of its own: staging the only file in a folder empties the folder, so the row *above* the selection goes too and there is nothing to land on upwards. `TreeSelection.surviving(below:rowCount:path:)` answers the other direction, tried after above, with the reported shape as its test. Driven both ways.
- [x] 2b.7 The redundant untracked listing: `refill` sends one per open directory per filesystem event and `fill` reloaded whatever came back. It compares against what the node already holds and returns when nothing changed — which is the flicker while staging.

## 3. The four trees, one at a time

- [ ] 3.1 The changes tree, which is the report. Driven capture of its keys before and after.
- [ ] 3.2 The project tree. Driven capture.
- [ ] 3.3 The branches tree, keeping its own ← and → over sections. Driven capture.
- [ ] 3.4 The pull-request file tree. Driven capture.

## 4. Finishing

- [ ] 4.1 Name the four outlines left alone — settings, the debugger's variables, the structure pane, the variable popup — in the design, so the sweep is known to be partial.
- [ ] 4.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
