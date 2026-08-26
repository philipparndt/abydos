## 1. Where a row's text ends

- [x] 1.1 Add `usedColumns` to `TerminalLine`: one past the last cell that is
      not `.blank`, zero for an untouched row. Scan backwards, so a row of
      ordinary text stops on the first comparison.
- [x] 1.2 Test it against the cases that decide it: trailing spaces, a space
      carrying a background colour (not blank — it is painted), the trailing
      cell of a wide glyph, and a row nothing has been written to.

## 2. The highlight stops there

- [x] 2.1 Pass `usedColumns` where `cells.count` is passed today — the two
      renderers in `TerminalView` and `text(in:)` on `TerminalGridReading`.
      Three call sites; the branch inside `columnRange` is untouched.
- [x] 2.2 Give a row strictly between the first and the last a minimum width of
      one cell, so a blank line in the middle of a selection still reads as
      part of it. Not the end rows — a first row anchored past its text shows
      nothing, and should.
- [x] 2.3 Test that a twelve-character row inside an eighty-column grid
      contributes twelve columns, that the rows between the ends do too, and
      that what a selection copies is byte-for-byte what it copied before.

## 3. A press cannot land past the text

- [x] 3.1 Clamp the column in `position(for:roundingToBoundary:)` to the row's
      `usedColumns` rather than to `emulator.metrics.columns`.
- [x] 3.2 Test both gestures: a press at column 40 on a row ending at 12
      anchors at 12, and a drag to column 40 reaches 12. *(Driven through the
      real events: `--select 0,40,0,60` reports `anchored=0,12`, and
      `--select 0,0,0,40` reports `to=0,12 rows=[0:0..<12/12]`.)*
- [x] 3.3 Check the two gestures that build a selection from a range rather
      than from a point — double-click and triple-click — still select what
      they did. `wordRange` and `lineSelection` read the line themselves.

## 4. Option makes a rectangle

- [x] 4.1 Add `isBlock` to `TerminalSelection` and branch on it in
      `columnRange(onRow:columns:)`: the columns between the two ends on every
      row, clamped to that row's width.
- [x] 4.2 Read Option in `mouseDown` and again in `mouseDragged`, so pressing or
      releasing it mid-drag switches the selection between the two kinds.
      *(Driven: `--select 0,9,3,12,option-mid` reports `pressedAsBlock=false`
      then `block=true`.)*
- [x] 4.3 Test the rectangle: eight rows of fixed-width output, columns 10 to
      18, gives eight lines of what stood there — and a row inside it whose
      text ends at 14 gives four characters and no padding.
- [x] 4.4 Test that the scrollback fix-up still follows a block selection when
      lines fall off the top. It moves both end points and should not care
      which kind it is holding.

## 5. Both renderers, both engines

- [x] 5.1 Confirm by test that the Core Text renderer and the Metal renderer
      ask the same question and get the same answer — one selection, the same
      columns per row. *(Made true by construction instead: both now call one
      `selectionRange(on:atRow:)`, so there is no second expression to
      disagree. The window layer has no test target — the driven `--select`
      report reads that same helper.)*
- [x] 5.2 Confirm the same for both engines. The helpers are on
      `TerminalGridReading`; the test is that a selection over the same rows
      copies the same text under each.

## 6. Finishing

- [x] 6.1 Drive the app and photograph a selection over ragged output, a block
      selection, and a selection spanning a blank line — the three things a
      reader cannot check from a test.
- [x] 6.2 Measure a redraw with a selection held over a full screen, with the
      machine load beside it, and compare with one held before the change.
      `usedColumns` is on the redraw path and the argument for not caching it
      is that it is cheap; that is a claim, so measure it.
- [x] 6.3 `make test` and `make warnings`, both clean, with the failures
      compared against a baseline taken by stashing the change — the suite
      carries pre-existing environment failures and several load-sensitive
      tests. *(`make warnings` clean. `make test` red in both states: 34 issues
      stashed, 40 with the change. **The comparison caught something real** —
      the first run had 46 issues and seven tests failing that the baseline did
      not, none of them about selection, because the new benchmark burned a
      second of busy CPU inside an ordinary `make test` and this suite is full
      of load-sensitive tests. Gated behind `ABYDOS_BENCH` like every other
      benchmark here; the run went from 74 s back to 26 s against the
      baseline's 23 s, and the extras fell to three — `aKeptRefIsAnOrdinaryBranch`,
      `aSweepTakesOnlyWhatIsOlderThanItWasAsked` and
      `saysWhichParameterIsBeingFilledIn` — a different three each run, all
      passing alone. The selection suites pass in the full run.)*
- [x] 6.4 Decide the open question in the design: whether a block selection is
      drawn differently from a line selection while a drag is in flight.
