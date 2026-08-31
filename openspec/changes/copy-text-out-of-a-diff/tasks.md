## 1. What a selection copies, before anything can be selected

- [x] 1.1 New `Sources/AbydosKit/Git/DiffTextSpan.swift`: two points of row and
      UTF-16 offset, ordered, and the string a run of row texts produces —
      first row cut at its offset, last row cut at its offset, `\n` between.
      No AppKit and no geometry
- [x] 1.2 `Tests/AbydosKitTests/DiffTextSpanTests.swift`, one claim per case:
      a run inside one row, a run across three, a pair given backwards, a
      selection ending at offset 0 of a row, an empty row in the middle, a
      selection of the whole thing, and a span whose rows have gone. Named as
      sentences, `@Test`/`#expect`
- [x] 1.3 `make test FILTER=DiffTextSpan` green

## 2. One place that says where a character is

- [x] 2.1 Pull `text(of row:)` and `textOrigin(of row:)` out of `draw(row:)` in
      `DiffView` — the marker's measured width included — and draw through
      them. Verify by driving `--commit-page` and `--pull-requests page,diff`
      before and after and comparing the reports and a screenshot line for line:
      this task changes no pixel
- [x] 2.2 A `CTLine` per row from the same attributed string the row draws,
      cached by row index, dropped wherever `rows` is rebuilt and on a theme or
      font change. Verify the cache empties: a report of its count after
      `arrange`, `whole:on` and a theme change
- [x] 2.3 `region(at:)` — `.numbers(row)`, `.text(row, side)`, `.header(row)` —
      off the same x boundaries the drawing uses, in both arrangements. Verify
      with a unit-free driven report that names the region for a set of points
      either side of each boundary, unified and side by side

## 3. The text selection

- [x] 3.1 `TextSelection` on `DiffView` — an ordered pair of row-and-offset,
      and the side it belongs to — mutually exclusive with the line selection:
      setting either clears the other
- [x] 3.2 `mouseDown`/`mouseDragged` over `.text` anchor and extend it, carrying
      the side through the drag, with `autoscroll(with:)`. A press with nothing
      dragged clears. Shift-click extends from where it began. Verify against
      the spec's scenarios by driven run
- [x] 3.3 The highlight: behind the glyphs, ending at the last covered
      character, a narrow mark for a row's line break, `Theme.current.selection(
      .text, hasKeyboard:)` so it greys when the keyboard leaves. Verify by
      screenshot of a three-row selection, then with the keyboard moved to the
      file list
- [x] 3.4 Side by side, a drag past the divider stays on the side it started on.
      Verify by screenshot and by the copied text being one file's lines
- [x] 3.5 Double-click takes the word under the pointer, triple-click takes the
      row's whole text; `selectAll(_:)` becomes select-all-text. Verify each by
      driven run reading back what would be copied

## 4. Copying it

- [x] 4.1 `copiedText` walks `rows` through `text(of:)` and `DiffTextSpan` —
      no `CTLine` built, nothing off-screen laid out
- [ ] 4.2 `copy(_:)` writes it to the general pasteboard; with no text selection
      and a line selection, it writes those lines instead. Verify ⌘C from the
      Edit menu reaches it in the pull request page, the commit page and the
      changes pane
- [x] 4.3 `validateMenuItem(_:)` enables *Copy* only when this view is the first
      responder and something is selected. Verify ⌘C in the file list beside the
      diff still copies what the list copies
- [x] 4.4 *Copy* as the first item of the menu over a diff whenever there is a
      selection, above what is already offered there. Verify with the existing
      `menu` step's report in both a read-only and a stageable diff

## 5. Lines move to the numbers

- [x] 5.1 A press or drag over `.numbers` fills the line selection — plain,
      shift and ⌘ behaving as they do today — and a drag over `.text` no longer
      does. A click on a hunk header still takes the hunk
- [x] 5.2 Verify nothing offered over a line selection moved: drive the changes
      pane and check *Stage Selected Lines*, *Discard Selected Lines* and the
      stash entry appear and are hidden exactly where they were, then stage a
      run of lines and confirm `git diff --cached` holds those lines and no
      others
- [ ] 5.3 Verify a pull request's remark still names its lines:
      `--pull-requests` with `menu:36-40` reads *Comment on Lines 36–40…*, and
      `write:36-40=…` lands where it did
- [ ] 5.4 A click on a remark still selects the remark, and a drag over its text
      selects text. Verify with `select-comment` and the new text step over the
      same rows

## 6. A driven run can say what happened

- [x] 6.1 `copiedTextForTesting` on `DiffView` and the page, and a separate
      `copyToPasteboardForTesting` that is the only thing writing the general
      pasteboard — a capture must not take away what somebody had copied
- [x] 6.2 `--pull-requests` steps `text:12.4-14.9` and `copy`, wired through
      `PullRequestReview.driveForTesting` beside `menu` and `select-comment`,
      documented in its comment the way the others are
- [x] 6.3 One driven script that is the proposal's complaint answered: open a
      pull request, pick a file, select a word, copy it, print it; then a run of
      three rows, copy, print; then ⌘A, copy, print the first and last lines.
      Its output goes in the change as the evidence

## 7. Cost, and finishing

- [x] 7.1 A drag down a 5,000-row diff and a scroll of the same diff, both timed
      through `Stopwatch.maySay` with `MachineLoad.said` beside the number — a
      figure without the load beside it cannot be told from a regression
- [x] 7.2 The awkward glyphs: a tab-indented line, an emoji inside a string
      literal, a hunk header in the bold face, and a remark — selected end to
      end and photographed, to see the highlight sit under the glyphs
- [ ] 7.3 Every diff in the window, once each: the pull request page, the commit
      page, the history pane, the changes pane and the editor's diff tab —
      select, copy, paste, and check the pasted text is the code with no marker
      and no number. Built with `make build BUNDLE_ID=de.rnd7.abydos.diffsel
      PIN_UUID=0`, run from `build/`, never installed
- [ ] 7.4 `make test` and `make warnings`, both clean, exit codes read rather
      than the output skimmed

## What is left, and what it needs

Four items are unticked because they cannot be run on this machine, not because
the code is missing. `gh` here is signed in to an internal enterprise host and
not to github.com, so the pull request page — the one place a *remark* lives in
a diff — cannot answer:

- **4.2** ⌘C is verified from the Edit menu in the commit page and in the
  history pane's read-only diff, at the real menu bar. The pull request page's
  own run is not in `evidence.md`.
- **5.3** and **5.4** are about a remark: `menu:36-40` reading *Comment on Lines
  36–40…*, and a click on a remark against a drag over its text. Both need a
  page with a review conversation in it.
- **7.3** covers two of the five places — the commit page and the history pane,
  which are the two values of `isReadOnly`. The pull request page, the editor's
  diff tab and the stash page all construct the same `DiffView` and were not
  driven.

**7.4** is half done and says so in `evidence.md`: `make warnings` exits 0, and
`make test` exits 1 on two suites this change cannot reach —
`ExternalDependenciesTests` (an expectation that depends on this machine's
`~/.gradle` cache) and `MermaidEveryKindLiveTests` (22 diagrams that the live
renderer did not draw here). Both are in `Tests/AbydosKitTests` against
`AbydosKit`; the only thing this change adds there is one file nothing else
references.

The `--pull-requests` steps for all of it are wired and documented (`text:`,
`text-left:`, `word:`, `row-text:`, `all`, `copied`, `copy`, `diff-menu`,
`diff-rows`, `regions:`, `measured`), so the run is a command rather than more
work.
