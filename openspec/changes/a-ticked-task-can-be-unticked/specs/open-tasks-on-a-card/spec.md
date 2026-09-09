# Open Tasks on a Card

## ADDED Requirements

### Requirement: A tick made on a card can be undone

A task ticked from a card's tip SHALL be undoable from where it was ticked and
from the keyboard. The row just ticked SHALL stay in the tip, drawn ticked and
dimmed with *Undo* at its end, until the tip is next re-read or the pointer
leaves; clicking it SHALL untick the same line. ⌘Z, and the Edit menu's *Undo
Tick*, SHALL untick the last tick this window made while the board or the tip
has the keyboard. The untick SHALL be written the way the tick is: only when the
line still reads as the ticked step with the same text, keeping every other byte,
and refusing — writing nothing and re-reading the tip — when the line has moved
on. Only ticks made in this window SHALL be undoable.

#### Scenario: A slipped click

- **GIVEN** a card's tip with thirty open tasks
- **WHEN** the wrong one is clicked, and then *Undo* on that row
- **THEN** the line in `tasks.md` reads `[ ]` again with the same text, and the
  row is open in the tip

#### Scenario: ⌘Z

- **GIVEN** a task just ticked from the tip
- **WHEN** ⌘Z is pressed while the board has the keyboard
- **THEN** the same line is unticked, and the Edit menu had named the action
  *Undo Tick*

#### Scenario: The file moved on

- **GIVEN** a task ticked from the tip, and an agent that has since rewritten
  that line
- **WHEN** *Undo* is clicked
- **THEN** nothing is written, and the tip says the task has moved and shows the
  file as it is now

#### Scenario: A driven run

- **GIVEN** a driven run that ticks a row through the tip
- **WHEN** its `undo` step runs
- **THEN** the run prints the line as the file has it, unticked, with the same
  text
