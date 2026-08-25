## Context

Selection lives in two places. `TerminalSelection` holds an anchor and a head in
absolute row space and answers, per row, which columns are in it;
`TerminalView` turns clicks into positions and draws the highlight. Both
renderers — the Core Text one and the Metal one — ask the same question:

    selection.columnRange(onRow: index, columns: line.cells.count)

`cells.count` is the width of the grid, not the width of the text. That single
argument is the whole of the reported fault: a row contributes columns up to the
grid's edge, so the highlight runs to the right margin whatever the row says,
and a press in the blank space beyond a short line anchors out there.

The copied text has never been wrong, because `TerminalLine.text(in:)` trims
trailing blanks on the way out. That is why this has lasted: nothing was
incorrect, only unreadable.

The helpers are on `TerminalGridReading`, which both our emulator and
libghostty-vt conform to (item 0485), so there is one implementation to change
and not two.

## Goals / Non-Goals

**Goals:**

- The highlight ends where the row's text ends.
- A press or drag beyond a row's text behaves as one at its end.
- Option held while dragging selects a rectangle.
- Both renderers and both engines change together, by construction.

**Non-Goals:**

- Changing what a selection copies for rows that have text on them. It is right
  now and stays byte-for-byte the same.
- Double-click, triple-click and Select All. They build selections from ranges
  the grid already computes and are unaffected.
- Selecting *through* a wrapped line as one logical line. A terminal does not
  record where a wrap happened, and guessing from a full last column is wrong
  for any program that fills the width on purpose.
- A keyboard selection mode.

## Decisions

### The row's own width, passed in, rather than a new kind of range

`TerminalLine` gains `usedColumns`: one past the last cell that is not
`.blank`, and zero for a row nothing has been written to. The three call sites
pass it in place of `cells.count`.

Two things follow that are worth stating. A cell holding a space *with a
background colour set* is not `.blank` — a coloured bar drawn out of spaces is
text as far as this is concerned, and selecting one highlights it, which is
right. And the trailing cell of a wide glyph is not blank either, so a row
ending in an emoji measures to the end of it.

Alternatives considered: a `TerminalSelection` that holds the grid and asks it
directly — rejected, because the type is `Sendable` and worth keeping so; and
trimming inside `columnRange` by passing the line — rejected as the same thing
with a wider signature.

### A blank row inside a selection keeps one cell of highlight

`usedColumns` of zero yields an empty range, so a blank row in the middle of a
selection would draw nothing — and a selection over a paragraph break would
look as though it had stopped there. Rows *strictly between* the first and the
last get a minimum width of one cell.

Strictly between, and not the ends: the first row of a selection whose anchor is
past its text, and the last whose head is at column zero, contribute nothing and
should show nothing.

### The modifier is read on every event, not only on the press

Option is read in `mouseDown` *and* in `mouseDragged`, so pressing or releasing
it mid-drag switches the selection between a rectangle and a run of lines under
the pointer. This is what iTerm2 and Terminal.app both do, and it is the only
behaviour that does not require knowing which way round to do it before starting.

There is no conflict to resolve. Option reaches a program only through
`forwardMouse`, and `forwardMouse` is not on this path: a drag either selects
(mouse tracking off) or is forwarded (tracking on, Shift not held), never both.

### A block is a flag on the selection, not a second type

`TerminalSelection` gains `isBlock`. `columnRange(onRow:columns:)` branches on
it: a block answers `min(anchor.column, head.column) ..< max(...)` on every row
it covers, clamped to that row's `usedColumns`; a line selection answers what it
answers now.

One branch in one method, and everything downstream — both renderers, `text(in:)`,
the scrollback fix-up that follows a selection as lines fall off the top — is
unchanged and correct for both. A separate `TerminalBlockSelection` would have
had to be threaded through every one of those.

### Copying a block trims each row

Each row of a block contributes its own slice with trailing blanks trimmed, and
the rows are joined with newlines — the same rule a line selection already uses,
applied per row. A block taken from a column of `ls -l` therefore pastes as a
list of values rather than as padded fixed-width fields.

## Risks / Trade-offs

- **`usedColumns` is a scan, and it is on the redraw path.** → Only when a
  selection exists, once per visible row, and it scans backwards from the end
  so it stops on the first row of ordinary text immediately. Worst case is a row
  of trailing blanks, which is a few hundred cell comparisons. If it shows up in
  `make timing`, the answer is to cache it on the line and invalidate on write —
  deliberately not done first, because a cache nobody needed would be a second
  thing to keep true.

- **A selection made before a resize is clamped by the new width.** → Already
  true and already commented in `columnRange`; `usedColumns` makes the clamp
  tighter, not different in kind.

- **Rows that are blank at their end but not empty.** A program that clears to
  end of line with a background colour leaves cells that are not `.blank`, so
  `usedColumns` reaches the margin and the highlight does too. → Correct, and
  the same thing every other terminal does: those cells are painted, so they are
  there to be selected.

- **Somebody may want the old behaviour for multi-row selections**, where the
  highlight runs to the edge to show the newline is included. → Not offered.
  Both reference terminals stop at the text, and the report is that this one
  does not.

## Open Questions

- Should a block selection be drawn differently from a line selection — a
  border, say — so the two are told apart while a drag is in flight? The
  modifier is the only signal today, and it is not on screen.
