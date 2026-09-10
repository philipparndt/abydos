# open-tasks-on-a-card Specification

## Purpose
TBD - created by archiving change a-ticked-task-can-be-unticked. Update Purpose after archive.
## Requirements
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

### Requirement: A tip can be reached with the pointer, from any card

The pointer SHALL be able to travel from a card to the tip below it and press a
box there, whatever the card's place in its column. The tip opens under its
card, and the next card of the column lies between the two, so the journey
crosses that card: crossing it SHALL neither close the tip nor move it.

**Two anchors, because the pointer is on the second card while the tip still
belongs to the first.** The card a tip is drawn under and the card a wait is
running for SHALL be remembered separately, and the waiting one SHALL become
the tip's only when that wait opens it. The pointer arriving inside the tip
SHALL drop any wait started by the crossing, so no other card's tip opens over
the one being read.

Reported 2026-09-10: the boxes could not be reached on any card but the last of
its column — the last being the only one with empty space below it rather than
another card. Two faults in the same journey. The tip closed the moment the
pointer touched the card below; and with that fixed, the crossing still moved
the open tip's anchor to that card, so the next redraw placed it under a card it
was not about and out from under the pointer reaching for it.

#### Scenario: Reaching the tip of a card with cards below it

- **GIVEN** a board whose In progress column holds three cards, and the tip of
  the first one open
- **WHEN** the pointer travels down into that tip, across the second card
- **THEN** the tip is still open, still about the first card, and has not moved

#### Scenario: Pressing a box once there

- **WHEN** a box in that tip is clicked
- **THEN** its line in `tasks.md` is ticked, exactly as a click on the last
  card's tip does

#### Scenario: Settling on the card below instead

- **GIVEN** the tip of the first card open
- **WHEN** the pointer comes to rest on the second card
- **THEN** after the same wait the tip is about the second card, drawn at the
  second card

### Requirement: A task's markdown is drawn, not shown

A task listed in a tip SHALL be drawn with its inline markdown rendered: bold
where the file has `**`, italic where it has `*`, and a fixed-pitch face where
it has backticks, with the markers themselves not drawn. A marker with no
closing partner SHALL be drawn as the character it is, and underscores SHALL be
left alone — a pair of them is nearly always one identifier.

These lines come out of a markdown checklist, and they were drawn exactly as the
file has them: a card showed `**Measure the build before settling this.**` with
the asterisks in the words. Reported 2026-09-10.

#### Scenario: A task with emphasis and an identifier in it

- **GIVEN** a task reading `5.2 **Measure the build before settling this.**
  \`buildWorkspace\` is a`
- **WHEN** its card's tip is drawn
- **THEN** the sentence is bold, `buildWorkspace` is fixed-pitch, and no
  asterisk or backtick is drawn

#### Scenario: Arithmetic in a task

- **GIVEN** a task containing `width * height`
- **WHEN** its card's tip is drawn
- **THEN** both asterisks are drawn, and nothing is italic
