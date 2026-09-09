## ADDED Requirements

### Requirement: Two whole files are shown side by side, aligned line by line

A file diff SHALL show the whole of both files, the left one as A and the right
one as B, as rows in which each row is a pair of lines — a line from each side,
or a line from one and a gap on the other — aligned by an in-process line diff.
Unchanged runs longer than a page are folded to a row saying how many lines are
hidden, which opens on a click, so that a diff of two large files starts on the
first change and not on the first line.

The diff is computed off the main thread, and the page says it is working until
it is done. A file whose text cannot be read as one of the encodings the editor
opens, or which the editor would open as bytes, is compared in the hex editor's
terms instead and this capability does not apply.

#### Scenario: an unchanged run is folded

- **GIVEN** two files that agree for their first two hundred lines
- **WHEN** the diff opens
- **THEN** the first row reads `200 Unchanged Lines`, and clicking it shows them

#### Scenario: a line only on the right

- **WHEN** B has a line A does not
- **THEN** the row shows the line on the right, coloured as added, and a gap on
  the left with no number

### Requirement: A change is joined to its counterpart by a curve between the halves

The gutter between the two halves SHALL draw, for every change, a curve from
the rows the change occupies on the left to the rows it occupies on the right,
coloured as the change is — added, removed, or changed — so that a line that
moved down thirty rows on the right is followed by the curve rather than by
counting. Only the curves whose rows intersect the visible rect are drawn.

#### Scenario: a change that moved

- **GIVEN** a six-line block removed near the foot of the left side and its
  two-line replacement thirty rows higher on the right
- **WHEN** both are on screen
- **THEN** one curve joins the left block to the right block, filled in the
  change's colour

#### Scenario: off screen

- **WHEN** a change's rows on both sides are below the visible rect
- **THEN** no curve is drawn for it

### Requirement: The characters that differ inside a changed line are marked

A changed pair SHALL have the characters that differ marked on both sides —
a changed pair being a row with a line on each side that are neither equal nor
wholly different — so that a comma added in the middle of a paragraph is a
comma and not a paragraph.
A pair with less than half of the shorter line in common is coloured whole. A
line longer than a few thousand characters is coloured whole, because the
intraline pass over a minified bundle is the cost being avoided.

#### Scenario: a comma

- **GIVEN** `Build here push into a development pod` on the left and `Build
  here, push into a development pod` on the right
- **WHEN** the row is drawn
- **THEN** only the comma is marked on the right, and the rest of the row is
  the changed colour without the mark

#### Scenario: a line replaced

- **GIVEN** a left line and a right line sharing three characters of forty
- **THEN** both are coloured whole, with no character marks

### Requirement: Changes are walked one at a time, and counted

The page SHALL number the changes — a change being one maximal run of rows
that are not equal — and SHALL say `Change n of m` for the one the view is on.
Two controls and two keys move to the next and the previous change, scrolling
it into view and marking it as current; the counts under the title are the
sum over all changes.

#### Scenario: the first change

- **WHEN** a diff with 40 changes opens
- **THEN** the view is scrolled to the first and the control reads `Change 1 of 40`

#### Scenario: next

- **GIVEN** `Change 1 of 40`
- **WHEN** next is pressed
- **THEN** the second change is scrolled into view and the control reads `Change 2 of 40`

#### Scenario: no changes

- **WHEN** the two files are identical
- **THEN** the control reads `No changes`, and the rows are shown unfolded

### Requirement: Long lines wrap when the editor wraps

The file diff SHALL follow the editor's word-wrap switch (⌥⌘Z): with it on, a
line wider than its half wraps within that half, a row is as tall as the
taller of its two halves, and the halves stay aligned row for row. The curves
join the tops of rows as before and the change count is unaffected. With the
switch off, each half scrolls sideways.

#### Scenario: a long line on one side

- **GIVEN** word wrap on, and a row whose left line takes three visual rows
  and whose right line takes one
- **WHEN** the row is drawn
- **THEN** it is three visual rows tall on both sides, and the next row starts
  below it on both

#### Scenario: the switch

- **GIVEN** a diff drawn wrapped, scrolled to change 12
- **WHEN** ⌥⌘Z turns wrap off
- **THEN** the rows are one visual row each, change 12 is still the current
  one and still in view, and each half can scroll sideways

### Requirement: The two halves scroll as one, and select as a diff does

Both halves SHALL scroll together vertically, because they are rows of one
alignment. Text in either half is selected and copied as `diff-selection`
says, and a selection belongs to one half. Each half has its own line numbers,
its own path in a bar above it with an A or B chip, and the language's colour
from the same colouring the diff view uses.

#### Scenario: the wheel

- **WHEN** the left half is scrolled by twenty rows
- **THEN** the right half shows the same twenty rows' counterparts

#### Scenario: a selection

- **WHEN** text is dragged over in the right half and copied
- **THEN** the clipboard holds the right half's text, as `diff-selection` would give it
