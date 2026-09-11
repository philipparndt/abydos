# Terminal

## ADDED Requirements

### Requirement: Making room at the bottom of the screen scrolls what was there

A line feed with the cursor on the last row of the scroll region SHALL scroll
the region up and send its top row into the scrollback, under either engine,
whatever program last set the region — a full-screen program that exited
without resetting it included. A shell that makes room below its prompt for a
listing SHALL find that room made by scrolling, and the rows that were on the
screen SHALL be in the scrollback rather than under the listing.

Reported 2026-09-09: `cd`, tab, tab shows the directory listing, and it
overwrites the output that was on the screen instead of scrolling it.

#### Scenario: A completion listing at the bottom of the screen

- **GIVEN** a pane whose prompt is on its last row, with output above it
- **WHEN** the shell lists completions taller than the rows left below the
  prompt
- **THEN** the output that was above the prompt is scrolled into the
  scrollback, the listing is drawn below the prompt, and no row that was on the
  screen is overwritten

#### Scenario: After a full-screen program

- **GIVEN** a pane in which a program set a scroll region narrower than the
  screen and exited
- **WHEN** the shell prints past the last row
- **THEN** the screen scrolls as if no region had been set

### Requirement: The rows a shell is told about are the rows it is drawn in

The row count reported to a pane's pseudo-terminal SHALL equal the rows the
pane draws for the program, after any strip the pane or tmux keeps for itself,
and SHALL be reported again when that changes — so a shell's arithmetic about
how many line feeds make room is done with the same number the pane paints.

#### Scenario: A hidden tmux status line

- **GIVEN** a pane running tmux with its status bar hidden by the app
- **WHEN** the shell inside asks how tall the terminal is
- **THEN** the answer is the rows it can draw in, and a listing that fills
  them lands where the shell put it
