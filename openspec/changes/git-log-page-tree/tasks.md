## 1. The view becomes an outline

- [x] 1.1 Replace the page's `fileTable` with an outline over `GitChangeNode`,
      keeping `[GitCommitFile]` as the source of truth and mapping it to
      `[GitChange]` to build the shape.
- [x] 1.2 Flat arrangement: one childless node per file, in today's order, so
      the outline draws exactly the rows the table did.
- [x] 1.3 Check the three delegate methods the two views share —
      `heightOfRow`, `rowViewForRow`, `selectionDidChange` — still answer for
      the commit table as well. *(`numberOfRows(in:)` became the commit list's
      alone and the file branch came out of `viewFor`, because an outline asks
      its own questions. The commit list still loads, selects and folds in the
      driven runs.)*
- [x] 1.4 Move selection to a path: `selectedRow` becomes the selected node's
      path, and the file is found from it.

## 2. Both arrangements

- [x] 2.1 Add the setting beside the other view preferences, off by default —
      the flat list is what the page shows today.
- [x] 2.2 Put the control in the page's header, and show which arrangement is in
      force. *(A two-segment control — list, folder — at the far end of the
      strip that already holds the Changes/Message tabs. **Not** in the split
      below it: that split's own comment records what a stack view in there
      cost, and the strip is a plain container. There is a View-menu item too,
      and the two keep each other in step. First attempt was the menu item
      alone, which is not a toggle — said so.)*
- [x] 2.3 Rebuild on toggle, keeping the selection on the same file and the diff
      on screen unchanged.
- [x] 2.4 Test both arrangements over one commit: the same files either way, the
      folder one grouping them, the flat one in today's order. *(Driven, over
      this repository's own commit: twelve files flat in git's order, then the
      same twelve under `openspec/`, `Sources/`, `Tests/`, and the selection on
      `GitChangeTree.swift` both times.)*

## 3. The star key

- [x] 3.1 `*` expands every folder, walking rows from the top, from whatever row
      the selection is on.
- [x] 3.2 Keep the selection, and do nothing in the flat arrangement.
- [x] 3.3 Test both: a shut tree fully open afterwards with the selection where
      it was, and `*` in the flat arrangement changing nothing. *(Driven: three
      `[shut]` folders, then the whole tree open. A `shut` step had to be added
      to the harness — the arrangement arrives open, so without it `*` has
      nothing to do and the test proves nothing.)*

## 4. Finishing

- [x] 4.1 Drive the page and photograph both arrangements of one commit, and the
      tree after `*`. *(Photographed. The flat rows are the same `name` +
      `directory` the table drew, because it is the same `CommitFileRowView`.
      **And it turned up a gap in `git-changes-detail`:** that change's spec
      says a file in a commit says how much changed, and the commit page's rows
      said nothing — only the working-copy views had been wired up. Fixed here,
      with one `git show --numstat` a commit: `+71 −4`, `+258 −12`, `+100`.)*
- [x] 4.2 `make test` and `make warnings`, both clean, with the failures compared
      against a baseline. *(`make warnings` clean. `make test`: 36 issues over
      six tests, five of them the families already failing before any of
      today's work; the sixth, `aBuildThatFailsIsReportedAtOnce`, passes alone
      in 0.4 s and is in `DebugRefusalLiveTests`, which touches nothing here.
      No benchmark was added.)*
- [x] 4.3 Decide the open question: whether the 300 pt column tense offers the
      folder arrangement too. *(No — the page only, and the code says so:
      `rebuildFileRows` asks for folders when `arrangement == .page` and the
      preference is on. A 300 pt column that hands its diffs to the editor area
      would spend four rows of indent on `Sources/AbydosKit/Git` to show one
      file. The preference is named for commit files, which is the page's
      list.)*

**No spec is made untrue.** `openspec/specs/git-pages` describes what the page
is and what a commit is; nothing there says how the files inside one are
arranged.
