## Purpose

Reading a diff line past the edge of its column: a horizontal scroller per text
column, the line numbers staying put while the text moves, the two halves of a
side-by-side diff linked or not, and the find bar reaching a match that is off
to the side.

## ADDED Requirements

### Requirement: A diff's text scrolls sideways when a line is wider than its column

A diff SHALL let its text be scrolled sideways whenever its widest line is wider
than the column it is drawn in: by a horizontal scroller along the bottom of the
column, by a horizontal trackpad swipe, and by a scroll wheel with ⇧ held, over
the column. Side by side there SHALL be one scroller per half, each the width of
its half; unified there SHALL be one. A column whose lines all fit SHALL show no
scroller.

Only the text SHALL move. The line numbers, the gutter and the selection marker
SHALL stay where they are, and a row's background colour SHALL run the full
width of its column whatever the offset — what scrolls is the code, not the
furniture that says which line it is.

The scrollers SHALL stay at the bottom of the visible diff while the rows scroll
up and down beneath them.

#### Scenario: a long line on the right

- **GIVEN** a side-by-side diff whose right half holds a line twice as wide as
  the half
- **WHEN** the right half's scroller is dragged to its end
- **THEN** the end of that line is visible, and the line numbers on the right
  have not moved

#### Scenario: everything fits

- **GIVEN** a diff whose lines are all narrower than their columns
- **THEN** no horizontal scroller is shown

#### Scenario: a swipe over one half

- **GIVEN** an unlinked side-by-side diff with long lines on both sides
- **WHEN** a horizontal swipe is made over the left half
- **THEN** the left half's text moves and the right half's does not

#### Scenario: unified

- **GIVEN** a unified diff with a line wider than the view
- **WHEN** it is scrolled sideways to the end
- **THEN** the end of the line is visible, and both line-number columns are
  where they were

### Requirement: The two halves of a side-by-side diff can be linked

A side-by-side diff SHALL offer a link button between the two halves' scrollers.
Linked, scrolling either half sideways — by its scroller, a swipe or the wheel —
SHALL move both by the same distance, each stopping at its own end. Unlinked,
each half SHALL move alone.

Linking SHALL be the default, and whether the halves are linked SHALL be
remembered across diffs, pages and launches. Linking two halves that are at
different offsets SHALL bring the other half to the offset of the one last
scrolled, so that linked always means level.

The button SHALL say which state it is in by its symbol — a closed link, or a
broken one — and by its tooltip.

#### Scenario: linked by default

- **GIVEN** a side-by-side diff opened for the first time, with long lines on
  both sides
- **WHEN** the right half is scrolled sideways by 200 points
- **THEN** the left half has moved by 200 points too

#### Scenario: one side ends sooner

- **GIVEN** linked halves, the left one's widest line 300 points past its edge
  and the right one's 900
- **WHEN** both are scrolled 600 points
- **THEN** the left half stops at its end, 300 points in, and the right is 600
  points in

#### Scenario: unlinking

- **GIVEN** linked halves
- **WHEN** the link button is pressed and the left half is scrolled
- **THEN** the right half stays where it was, and the button shows a broken link

#### Scenario: linking again levels them

- **GIVEN** unlinked halves, the left at 400 points and the right at 0, the
  right scrolled last
- **WHEN** the link button is pressed
- **THEN** the left half moves to 0

#### Scenario: remembered

- **GIVEN** the halves unlinked
- **WHEN** another file is shown, or the app is started again
- **THEN** the halves are still unlinked

### Requirement: What brings a column into view brings it sideways too

Anything that brings a place in the diff into view on the reader's behalf —
today, the find bar making a match current — SHALL also scroll that place's column sideways far enough to show it, when
it is off to either side; linked halves move together as they do for any other
sideways scroll. A place already visible SHALL NOT cause a sideways move.

A new diff — another file, the whole-file switch — SHALL start at the left edge.
Switching between unified and side by side SHALL start at the left edge too: the
two arrangements have different column widths, and an offset carried across
would point at a different part of the line.

#### Scenario: a match off to the right

- **GIVEN** the find bar open and a match at column 180 of a line, off the right
  edge of its half
- **WHEN** it becomes current
- **THEN** its half is scrolled sideways until the match is visible, and it is
  selected

#### Scenario: a match already visible

- **GIVEN** the halves scrolled 100 points to the right and the current match
  visible
- **WHEN** the next match, also visible, becomes current
- **THEN** nothing scrolls sideways

#### Scenario: another file starts at the left

- **GIVEN** a diff scrolled sideways
- **WHEN** another file is chosen
- **THEN** its text starts at the left edge

### Requirement: Selection follows the text where it is drawn

A text selection SHALL land on the characters under the pointer whatever the
sideways offset, and SHALL be drawn behind those characters as they move. A
selection dragged past the edge of its column SHALL NOT be required to scroll the
column; extending it there selects to the last visible character, and the
scroller or the keyboard brings more into view.

#### Scenario: selecting scrolled text

- **GIVEN** the right half scrolled 300 points to the right
- **WHEN** a word visible at the half's left edge is double-clicked
- **THEN** that word is selected and copied, not the word that would be there
  unscrolled
