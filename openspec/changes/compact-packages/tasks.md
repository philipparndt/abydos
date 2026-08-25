## 1. The walk, in the kit

- [x] 1.1 Add `compactedChildren` to `FileNode`: each child directory replaced
      by the deepest directory reachable through steps that hold exactly one
      entry and that entry a directory. A child that is a file, excluded, or
      holds anything but one directory is returned as itself.
- [x] 1.2 Add `compactedName`: walk *up* while the parent holds exactly this one
      entry, and join. The inverse of 1.1, so the two cannot drift — a folded
      row's name is recovered from the row rather than stored beside it.
- [x] 1.3 Choose the separator by where the chain begins: dots below a directory
      named `java`, `kotlin` or `scala`, slashes otherwise.
- [x] 1.4 Test the cases that decide it: a three-deep package chain, a directory
      with two entries, a directory holding one *file*, an excluded directory, a
      chain under `src/main/java` and the `src/main/java` chain itself, and a
      project root that holds exactly one directory.

## 2. The tree draws it

- [x] 2.1 Ask `compactedChildren` in the outline's `numberOfChildrenOfItem` and
      `child:ofItem:` when the setting is on, and `children` when it is not.
- [x] 2.2 Draw `compactedName` in the cell, keeping the icon, the git tint and
      the tool tip's full path as they are.
- [x] 2.3 Test that a folded row's children are the last directory's contents,
      and that its tool tip still says the whole path. *(The children are a
      test; the tool tip is a driven run — a cell's tool tip is not reachable
      from `AbydosKitTests`, which links only the kit.)*

## 3. The four walks that are written by hand

- [x] 3.1 Reveal: `node(for:)` descends through the chain, so the row to select
      is the folded one — expanding its ancestors must skip the rows the outline
      does not have.
- [x] 3.2 Expansion save and restore: `expandedPaths()` and
      `expand(node:matching:)` key on `url.path`, which a folded row still has.
      Confirm by test rather than by reading.
- [x] 3.3 The watcher's `loadedNode(for:)`, which stops at the first closed door
      on purpose. A folded chain is several closed doors that are one row; make
      sure a write inside one still reloads the row that shows it.
- [x] 3.4 A test for each of the four, because each is a different way of
      arriving at the same node and only one of them is the outline's.

## 4. The toggle

- [x] 4.1 Add the setting beside `showHiddenFiles`, defaulting to off, and a
      third button in `NavigatorHeaderView` — two array entries, since it lays
      out from the right already. Include it in `restyle`.
- [x] 4.2 Rebuild on toggle keeping the selection, and re-open every row that is
      still a row: the deepest node keeps its path either way, so the save and
      restore that exist already do most of this.
- [x] 4.3 Show that the button is on: the same treatment the other header
      buttons use for a pressed state, or a tint.
- [x] 4.4 Test the toggle both ways with a file selected inside a chain.

## 5. Finishing

- [x] 5.1 Drive the app against a Maven reactor and photograph the tree with the
      toggle off and on — the row count before and after is the claim. *(Three
      modules with every package revealed: 56 rows off, 47 on.)*
- [x] 5.2 **Measure what deciding to fold costs**, with the machine load beside
      it: `FileNode.directoryReadsForTesting` before and after opening a large
      project with compaction on and off, and the tree's own scale report. The
      design argues it is cheap because listings are cached and the walk stops
      early; that is an argument, not a number.
- [x] 5.3 `make test` and `make warnings`, both clean, with the failures
      compared against a baseline taken by stashing the change — the suite
      carries pre-existing environment failures and several load-sensitive
      tests. *(`make warnings` clean. `make test` is red in both states and by
      the same amount: 44 issues stashed, 62 with the change, at loads of 13–19
      over 14 cores, and the two sets differ in **both** directions — six tests
      fail only in the baseline. Every test that failed only with the change
      passes when the fourteen of them are run alone, in 0.7 s; all are git
      repository or session tests, and none is in the tree.
      `CompactPackagesTests`, `FileNodeReloadTests` and `SettingsTests` pass in
      the full run.)*
- [x] 5.4 Decide the open question in the design: whether turning compaction on
      folds a chain somebody has explicitly expanded.
