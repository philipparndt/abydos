## 1. Where a row's text ends

- [ ] 1.1 Add `usedColumns` to `TerminalLine`: one past the last cell that is
      not `.blank`, zero for an untouched row. Scan backwards, so a row of
      ordinary text stops on the first comparison.
- [ ] 1.2 Test it against the cases that decide it: trailing spaces, a space
      carrying a background colour (not blank — it is painted), the trailing
      cell of a wide glyph, and a row nothing has been written to.

## 2. The highlight stops there

- [ ] 2.1 Pass `usedColumns` where `cells.count` is passed today — the two
      renderers in `TerminalView` and `text(in:)` on `TerminalGridReading`.
      Three call sites; the branch inside `columnRange` is untouched.
- [ ] 2.2 Give a row strictly between the first and the last a minimum width of
      one cell, so a blank line in the middle of a selection still reads as
      part of it. Not the end rows — a first row anchored past its text shows
      nothing, and should.
- [ ] 2.3 Test that a twelve-character row inside an eighty-column grid
      contributes twelve columns, that the rows between the ends do too, and
      that what a selection copies is byte-for-byte what it copied before.

## 3. A press cannot land past the text

- [ ] 3.1 Clamp the column in `position(for:roundingToBoundary:)` to the row's
      `usedColumns` rather than to `emulator.metrics.columns`.
- [ ] 3.2 Test both gestures: a press at column 40 on a row ending at 12
      anchors at 12, and a drag to column 40 reaches 12.
- [ ] 3.3 Check the two gestures that build a selection from a range rather
      than from a point — double-click and triple-click — still select what
      they did. `wordRange` and `lineSelection` read the line themselves.

## 4. Option makes a rectangle

- [ ] 4.1 Add `isBlock` to `TerminalSelection` and branch on it in
      `columnRange(onRow:columns:)`: the columns between the two ends on every
      row, clamped to that row's width.
- [ ] 4.2 Read Option in `mouseDown` and again in `mouseDragged`, so pressing or
      releasing it mid-drag switches the selection between the two kinds.
- [ ] 4.3 Test the rectangle: eight rows of fixed-width output, columns 10 to
      18, gives eight lines of what stood there — and a row inside it whose
      text ends at 14 gives four characters and no padding.
- [ ] 4.4 Test that the scrollback fix-up still follows a block selection when
      lines fall off the top. It moves both end points and should not care
      which kind it is holding.

## 5. Both renderers, both engines

- [ ] 5.1 Confirm by test that the Core Text renderer and the Metal renderer
      ask the same question and get the same answer — one selection, the same
      columns per row.
- [ ] 5.2 Confirm the same for both engines. The helpers are on
      `TerminalGridReading`; the test is that a selection over the same rows
      copies the same text under each.

## 6. Finishing

- [ ] 6.1 Drive the app and photograph a selection over ragged output, a block
      selection, and a selection spanning a blank line — the three things a
      reader cannot check from a test.
- [ ] 6.2 Measure a redraw with a selection held over a full screen, with the
      machine load beside it, and compare with one held before the change.
      `usedColumns` is on the redraw path and the argument for not caching it
      is that it is cheap; that is a claim, so measure it.
- [ ] 6.3 `make test` and `make warnings`, both clean, with the failures
      compared against a baseline taken by stashing the change — the suite
      carries pre-existing environment failures and several load-sensitive
      tests.
- [ ] 6.4 Decide the open question in the design: whether a block selection is
      drawn differently from a line selection while a drag is in flight.
