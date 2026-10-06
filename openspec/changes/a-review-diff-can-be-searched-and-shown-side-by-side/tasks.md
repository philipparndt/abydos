## 1. What a match is, in AbydosKit

- [x] 1.1 `Sources/AbydosKit/Search/DiffSearch.swift`: takes the searchable
  lines and a query with `SearchOptions`, compiles `TextSearch`'s pattern once
  and matches it line by line, returning `(line, utf16Range)` per match in
  order; no match spans two lines and none is empty. Comment says why per line
  and not joined (a lone `\r` in a CRLF diff). Verified by 1.2.
- [x] 1.2 `DiffSearchTests` (swift-testing, named as sentences): a removed and an
  added line both match; git's prefix is not text; whole word and match case
  behave as in `TextSearchTests`; `a\nb` as a regex finds nothing; a lone `\r`
  moves nothing; an empty match is not one; ranges are UTF-16; the match limit
  holds. The side-by-side count is the view's rule and is checked by driving
  (5.2). `make test FILTER=DiffSearchTests` passes, 10 tests.

## 2. `DiffView` draws and reveals matches

- [x] 2.1 `DiffView` gains the rows-to-searchable-lines step: code rows only,
  `text(ofRow:in:)` per column, the left half of an unchanged pair left out;
  headers, scope lines, preamble and remark rows left out. Verified by a driven
  `find-status` over a diff with a remark holding the query (task 5.2).
- [x] 2.2 `search(for:options:)`, `stepMatch(by:)`, `endSearch()` hold the query,
  matches and current one, re-run after every rebuild;
  `DiffView+Drawing` paints `searchMatchBackground` behind each match on
  visible rows and `searchMatchCurrentBackground` behind the current, behind the
  glyphs as the text selection is, finding visible matches by binary search on
  row. Verified by a screenshot from a driven run in both arrangements.
- [x] 2.3 Revealing the current match scrolls the row into view and sets the text
  selection to the match through `textRun`, so ⌘C copies it. Verified by the
  driven `copied` step after `find-next` returning the match text.
- [x] 2.4 A key for a row that survives a rebuild — side, line number on that
  side, offset — and the lookup back from it, used both for the current match
  and for the top visible row. Verified by 5.2's arrangement and whole-file
  steps.
- [x] 2.5 `Scripts/file-size.sh` still passes for every `DiffView*.swift`; if
  `DiffView.swift` or `DiffView+Drawing.swift` would pass the limit, the search
  goes to `DiffView+Search.swift`.

## 3. The find bar on the pull request page

- [x] 3.1 `PullRequestPage+Find.swift`: a `FindBar` above the diff scroll view,
  hidden until asked for, find-only (`setReplacing(false)`, replace callbacks
  left nil); `findInFile(_:)` opens it, seeded from the diff's text selection,
  and focuses its field; `findNext(_:)` / `findPrevious(_:)` and the bar's own
  keys step and wrap; ⎋ closes it, clears the marks and gives the diff the
  keyboard. Verified by driving ⌘F with the keyboard on the file list and on the
  diff (5.2).
- [x] 3.2 The first current match is the first at or below the top visible row;
  the bar's status is `FindBar.setStatus` with the count and index. Verified by
  the driven "starting where the reader is" scenario.
- [x] 3.3 After every `setDiff`, picture load, whole-file switch and arrangement
  switch, the search re-runs with the bar's query and options and keeps the
  current match by its key (2.4); a picture or a diff with no textual changes
  reports no matches. Verified by 5.2.
- [x] 3.4 `PullRequestPage.swift` stays under the length limit
  (`Scripts/file-size.sh`).

## 4. The side-by-side switch

- [x] 4.1 A `DrawnCheckbox` *Side by side* beside *Whole file*, toggling
  `Settings.diffIsSideBySide`, with a tooltip; the page sets it from the setting
  on the settings notification so a menu flip moves it. Verified by
  `side-by-side:on` and the menu step in 5.2.
- [x] 4.2 Before the rows are rebuilt for an arrangement change, the page
  remembers the top visible row's key and scrolls that row back to the top
  after. Verified by the driven "half-way down" scenario.
- [x] 4.3 View ▸ Diff ▸ Side by Side Diff takes its tick from
  `MainWindowController.validateMenuItem` instead of storing it at build and on
  click (`AppDelegate+Menu.swift`, `MainWindowController+Layout.swift`); the same
  for Show Diff Headers, which has the same fault. Verified by flipping the page
  switch and reading the menu through the driven menu check.
- [x] 4.4 The header controls still follow the zoom, as the existing
  requirement says: one more control in the row is checked at the largest zoom
  in a driven screenshot, and nothing truncates the heading off entirely.
  Done at 1.6×: the header scales with the new switch in it. The find bar's
  own controls do not scale — `FindBar` behaves the same over the editor — and
  that is recorded in the design's risks rather than fixed here.

## 5. Driving and checking

- [x] 5.1 `PullRequestReview.driveForTesting`: `find:<query>`, `find-next`,
  `find-previous`, `find-status`, `find-close`, `side-by-side:on|off`, each
  documented in the list above it in the house style.
- [x] 5.2 A driven run against a scratch repository under the scratchpad (never
  a real checkout), with a throwaway bundle id, `PIN_UUID=0` and a pre-seeded
  throwaway defaults domain, launch guarded to the project asked for, that walks
  every scenario in `specs/diff-search/spec.md` and `specs/pull-requests/spec.md`
  and records the output. Find out first how the existing driven review runs
  get a pull request without a real one (not checked while proposing); the run
  must not create, comment on or review anything on GitHub.
  Done through `ABYDOS_GH` pointing at a scratch `fake-gh` that answers from
  the fixture's own git and refuses every write. The run found a crash
  (`Int` of a non-finite `visibleRect`) and a place-keeping conflict, both
  fixed and driven again.
- [x] 5.3 The search cost measured on a generated 20,000-line whole-file diff,
  with the load printed beside it by `MachineLoad.said`; typing a query stays
  interactive. 3.7 ms at load 0.3 per core, debug build.
- [x] 5.4 No `.abydos/backlog/spec/*.md` file is made untrue — that backlog is
  retired and its account now lives in `openspec/specs`, which this change's
  deltas update on archive.
- [x] 5.5 `make test` and `make warnings`, both clean, by their exit codes:
  4,648 tests passed (exit 0), no warnings (exit 0).
