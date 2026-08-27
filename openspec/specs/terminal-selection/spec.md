# Terminal selection

## Purpose

Where a selection in the terminal begins and ends: at the text on a row rather than at the width of the screen, in a rectangle when Option is held, and the same way under either renderer and either engine.

## Requirements

### Requirement: A selection's highlight ends where the row's text ends

A row SHALL contribute to a selection only the columns up to the end of its own
text, and never to the edge of the grid.

The grid is as wide as the window; a row of output usually is not. Highlighting
to the margin lights up eighty columns of nothing beside a two-word prompt, and
across several rows it makes a solid rectangle with the text somewhere inside
it — so what is selected has to be worked out rather than seen.

What is copied does not change. Trailing blanks were already trimmed on the way
out, which is why this fault survived: nothing was ever wrong, only unreadable.

#### Scenario: a short line inside a wide window

- **GIVEN** an 80-column terminal whose row 4 holds twelve characters
- **WHEN** a selection covers row 4
- **THEN** the highlight on that row is twelve columns wide, not eighty

#### Scenario: the rows between the ends

- **GIVEN** a selection running from row 2 to row 6
- **THEN** each of rows 3, 4 and 5 is highlighted to the end of its own text
  rather than to the right edge

#### Scenario: what is copied is unchanged

- **WHEN** a selection over rows with text on them is copied
- **THEN** the text is exactly what the same selection produced before, one
  newline per row, trailing blanks trimmed

### Requirement: A press or drag beyond a row's text lands at its end

A position taken from the pointer SHALL be no further right than the end of the
text on the row it is on.

Anchoring in the blank space past the end of a line is anchoring at a place with
nothing in it: the drag begins somewhere the highlight cannot show and the
copied text does not include.

#### Scenario: pressing past the end

- **GIVEN** a row whose text ends at column 12
- **WHEN** the pointer presses at column 40 on that row
- **THEN** the selection is anchored at column 12

#### Scenario: dragging past the end

- **GIVEN** a selection being dragged along a row whose text ends at column 12
- **WHEN** the pointer moves to column 40 on that row
- **THEN** the selection reaches column 12 and no further

#### Scenario: a row with a coloured background is text

- **GIVEN** a row where a program has written spaces with a background colour
  set out to column 60
- **THEN** those cells are selectable, because they are painted

### Requirement: A blank row inside a selection stays visibly selected

A blank row SHALL still carry a mark at least one cell wide when it lies
strictly between the first and last rows of a selection.

A blank row contributes no columns, so it would draw nothing — and a selection
over a paragraph break would look as though it had ended there. The ends are
different: a first row anchored past its text, or a last row reached at column
zero, contribute nothing and show nothing, which is correct.

#### Scenario: a blank line in the middle

- **GIVEN** a selection from row 2 to row 6 where row 4 is empty
- **THEN** row 4 carries a mark, so the selection reads as continuous

#### Scenario: an end row with nothing in it

- **GIVEN** a selection whose last row is reached at column 0
- **THEN** that row shows no highlight

### Requirement: Option held while dragging selects a rectangle

While Option is held, a drag SHALL select the same columns on every row it
covers rather than a run of lines, and copying one SHALL join those rows with
newlines with each row trimmed of trailing blanks.

Terminal output is full of columns — `ls -l`, `ps`, `git log --oneline`, a table
— and taking one column out of it is otherwise not possible at all. Option is
the modifier iTerm2 and Terminal.app both use for it.

Each row of a block is still bounded by its own text, so a rectangle drawn over
rows of unequal length gives back what is on each of them and nothing else.

#### Scenario: taking one column

- **GIVEN** rows of fixed-width output
- **WHEN** a drag with Option held covers columns 10 to 18 of rows 2 to 9
- **THEN** the selection is that rectangle, and copying it gives eight lines of
  what stood in those columns

#### Scenario: a rectangle over rows of unequal length

- **GIVEN** a block selection covering columns 10 to 30
- **AND** a row inside it whose text ends at column 14
- **THEN** that row contributes columns 10 to 14 and no padding

#### Scenario: the modifier is read as the drag goes

- **GIVEN** a drag in flight with Option not held
- **WHEN** Option is pressed without releasing the button
- **THEN** the selection becomes a rectangle, and releasing Option makes it a
  run of lines again

#### Scenario: it does not disturb a program that tracks the mouse

- **GIVEN** a program that has asked for mouse events
- **THEN** Option-dragging forwards events to it as before, because a drag
  either selects or is forwarded and never both

### Requirement: Both renderers and both engines answer the same way

The selection geometry SHALL be computed in one place, used by the Core Text
renderer and the Metal renderer alike, and by both terminal engines.

Two implementations of where a highlight stops is two things to keep in
agreement, and the pair would disagree first on exactly the rows this change is
about. The helpers already sit on `TerminalGridReading`, which both engines
conform to.

#### Scenario: the same selection under either renderer

- **WHEN** the same selection is drawn by the Core Text renderer and by the
  Metal renderer
- **THEN** the highlighted columns on every row are the same

#### Scenario: the same selection under either engine

- **WHEN** the same rows are selected in a pane emulated by our own emulator and
  in one emulated by libghostty-vt
- **THEN** the selection covers the same columns and copies the same text
