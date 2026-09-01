## 1. Name the cause before writing anything

- [ ] 1.1 Driven, on a scratch repository with an untracked nested folder: reproduce → losing the selection, and capture what runs between the key and the lost selection.
- [ ] 1.2 Write the mechanism into the design, replacing the compaction hypothesis with what was found — including if it is the hypothesis.

## 2. The behaviour

- [ ] 2.1 Add the tree behaviour to `Controls/`: holding a selection across a rebuild, restoring it, and the fallback when the row has gone.
- [ ] 2.2 Make a failed restore fall back to the nearest surviving row through `TreeSelection.surviving`, and log that it missed.
- [ ] 2.3 Settle the row-identity question from 1.2 and put whatever arithmetic it needs in AbydosKit beside `TreeSelection`, with tests.

## 2b. The two reports that arrived after the proposal

- [ ] 2b.1 Apply the fallback the pane already computes when staging takes the selected row away, so the neighbour is selected.
- [ ] 2b.2 Give the changes tree a row view that draws the app's selection through `Theme.selection`, the way `NavigatorRowView` does, instead of leaving AppKit to paint its band.
- [ ] 2b.3 Check the other three trees draw the app's selection too, and say in the design which of the four did not.
- [ ] 2b.4 Make the log page's detail file list take the keyboard when it is clicked into, so the arrows stop going to the commit list above it.
- [ ] 2b.5 Check the same for the other three trees: click a row, then press ↓, and say which trees did not already move.

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
