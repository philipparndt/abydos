# open-tasks-on-a-card Specification

## Purpose
TBD - created by archiving change a-ticked-task-can-be-unticked. Update Purpose after archive.
## Requirements
### Requirement: A tick made on a card can be undone

A task ticked from a card's tip SHALL be undoable from where it was ticked and
from the keyboard. **Every** row ticked while the tip has been open SHALL stay
in it, drawn ticked and dimmed with *Undo* at its end, each one clickable to
untick that same line, in any order — not only the newest, which was the one
tick a tip offered a way back on until 2026-09-10. A row SHALL keep the place
its line gives it, so ticking one does not move the others. The ticks SHALL be
forgotten when the tip closes, after which ⌘Z through the pane is the way back.

*Undo* SHALL be drawn at the row's trailing edge, with the task's words
wrapping short of it. Flowed after the words it was drawn nowhere on the rows
that fill both their lines, which is most of them. ⌘Z, and the Edit menu's *Undo
Tick*, SHALL untick the last tick this window made while the board or the tip
has the keyboard. The untick SHALL be written the way the tick is: only when the
line still reads as the ticked step with the same text, keeping every other byte,
and refusing — writing nothing and re-reading the tip — when the line has moved
on. Only ticks made in this window SHALL be undoable.

#### Scenario: Several ticks, and the first one taken back

- **GIVEN** a card's tip open, and two tasks ticked in it one after the other
- **WHEN** *Undo* is clicked on the first of the two
- **THEN** that line reads `[ ]` again and the second stays ticked, and both
  rows had been offered a way back at once

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

### Requirement: A card in progress lists its open tasks on the pointer resting on it

A card in the In progress column SHALL show, when the pointer has rested on it
for the app's tooltip delay, a tip listing every task of its checklist that is
still unticked, headed by how many are open of how many. The tip is in the
app's own type and ground — the drawn tooltip's, not the system's — placed
under the card's leading edge, or above the card where there is no room below,
and bounded to a third of the screen's height, scrolling past that.

Each row is the step's first line as it is written in the file, with the
number or word that leads it, wrapped to two lines and then cut. Ticked tasks
are not listed: the fraction on the card already counts them.

The tip is shown for both records — a change with some tasks ticked and some
not, and a backlog item in `in-progress/` — read from the same checklist the
card's fraction is counted from. It SHALL NOT be shown for a card in any other
column: a Ready card has nothing verified, and a Complete card has nothing
open.

The file is read when the tip opens, not while the pointer moves and not while
the board draws.

#### Scenario: a change part-way through

- **GIVEN** a change's card in In progress reading `4/30`
- **WHEN** the pointer rests on it for half a second
- **THEN** a tip opens under the card headed `26 open of 30`, listing the
  twenty-six unticked tasks in the order they are in `tasks.md`, each with a
  box

#### Scenario: an item being worked in a worktree

- **GIVEN** an item's card reading `3/6 in the worktree`
- **WHEN** the pointer rests on it
- **THEN** the tip lists the three steps unticked in the worktree's copy, not
  the six in the project's

#### Scenario: a card that is not in progress

- **GIVEN** a change's card in Ready, or in Complete
- **WHEN** the pointer rests on it
- **THEN** no tip opens

#### Scenario: more tasks than fit

- **GIVEN** a change with forty open tasks on a screen where twenty rows make a
  third of its height
- **WHEN** the tip opens
- **THEN** it is as tall as twenty rows and scrolls to the rest, and no row is
  replaced by a count of what was left out

#### Scenario: a long step

- **GIVEN** an open step whose first line is a hundred and twenty characters
  and whose continuation runs three more
- **WHEN** it is listed
- **THEN** the row shows the first line wrapped to two lines and cut, and none
  of the continuation

### Requirement: A box ticked in the tip ticks that line of the file

A click on a row of the tip SHALL rewrite that step's line from `- [ ]` to
`- [x]` in the file the card's checklist was read from — the worktree's copy
for an item being worked in one, the project's copy otherwise, and `tasks.md`
for a change — written atomically, with every other byte of the file kept as
it was: the bullet character, the indentation, the continuation lines and the
final newline or its absence.

The line is identified by its position, not by its words, and it SHALL be
checked at the moment of writing: if that line no longer reads as an unticked
step, nothing is written, the tip reloads its list from the file, and the
person sees what is there now. A file that cannot be written SHALL be said so
in the tip, naming the file, and nothing else changes.

After a tick the board follows the write the way it follows any other — the
fraction, the bar and the column — and the tip drops the row. Ticking the last
open task moves the card out of In progress and closes the tip.

The tip SHALL NOT offer to untick: a ticked task is not listed, and undoing a
tick is the file's business.

#### Scenario: ticking one task

- **GIVEN** the tip open on a change reading `4/30`
- **WHEN** the row for `3.2 Tests, named as claims` is clicked
- **THEN** that line of `tasks.md` reads `- [x] 3.2 Tests, named as claims`
  and no other byte of the file has changed
- **AND** the card reads `5/30` and the tip is headed `25 open of 30` without
  that row

#### Scenario: ticking the last open task

- **GIVEN** the tip open on a change reading `29/30`
- **WHEN** its one row is clicked
- **THEN** the card moves to Complete and the tip closes

#### Scenario: the worktree's copy is what is written

- **GIVEN** the tip open on an item reading `3/6 in the worktree`
- **WHEN** a row is clicked
- **THEN** the worktree's copy of the item has four ticked and the project's
  copy is untouched

#### Scenario: two steps with the same words

- **GIVEN** a `tasks.md` with `- [ ] Tests` under two headings, both open
- **WHEN** the second is clicked in the tip
- **THEN** the second line is ticked and the first still reads `- [ ]`

#### Scenario: the file changed under the tip

- **GIVEN** the tip open, and an agent in a terminal having since rewritten
  `tasks.md` so that the clicked row's line is now a different task
- **WHEN** the row is clicked
- **THEN** nothing is written, and the tip shows the list as the file has it
  now

#### Scenario: a worktree that is gone

- **GIVEN** the tip open on an item whose worktree copy has been deleted since
- **WHEN** a row is clicked
- **THEN** the tip says the file could not be written and names it, and the
  next reload draws the card from the project's copy, saying so

#### Scenario: a tick made elsewhere while the tip is open

- **GIVEN** the tip open on a change
- **WHEN** an agent ticks a task in a terminal
- **THEN** the tip's list loses that row without being reopened

### Requirement: The tip takes the pointer, and goes when the pointer has left

Unlike the app's tooltip, which ignores the mouse, the tip SHALL answer it: it
stays while the pointer is on the card that opened it or inside the tip, and
crossing the gap between the two SHALL NOT close it. It SHALL close when the
pointer has been on neither for a quarter of a second, on a click anywhere
that is not the tip, when the column scrolls, when a drag begins, when a menu
opens, when a reload leaves the card outside In progress, and when the window
stops being key. It SHALL never take focus from the window.

Only one tip is open at a time, and moving the pointer to another card in
progress opens that card's tip in its place after the same delay.

#### Scenario: moving from the card into the tip

- **GIVEN** the tip open under a card
- **WHEN** the pointer moves off the card's foot, across the gap, into the tip
- **THEN** the tip stays open

#### Scenario: moving away

- **GIVEN** the tip open
- **WHEN** the pointer moves to an empty part of the column and rests there
- **THEN** the tip is gone within a quarter of a second

#### Scenario: right-clicking the card

- **GIVEN** the tip open
- **WHEN** the card's context menu is opened
- **THEN** the tip closes before the menu shows

#### Scenario: scrolling the column

- **GIVEN** the tip open
- **WHEN** the column is scrolled
- **THEN** the tip closes

#### Scenario: focus stays where it was

- **GIVEN** the editor has focus and the tip opens over the panel
- **WHEN** a row is clicked
- **THEN** the task is ticked and the editor still has focus

### Requirement: A driven run reads the tip and ticks through it

A driven run SHALL be able to open the tip on a named card — a change by name,
an item by number — and print its heading and its rows, and to tick the n-th
open task through the tip's own click handler and print the card's fraction
afterwards. Both go through the same open and the same click a pointer would,
so a harness cannot pass with the hit test wired to nothing. Because a child
window is invisible to a capture of the main one, the tip SHALL draw itself to
a PNG on request. The verbs are declared on the pane, whose state they read.

#### Scenario: reading the tip

- **WHEN** a run is given `--backlog-tasks find-bands-follow-soft-wrap`
- **THEN** it prints `26 open of 30` and the twenty-six rows in order, and
  exits

#### Scenario: ticking through it

- **WHEN** a run is given `--backlog-tick find-bands-follow-soft-wrap:3`
- **THEN** the third open task's line in `tasks.md` is ticked, and the run
  prints the card's new fraction

#### Scenario: a card that has no tip

- **WHEN** a run is given `--backlog-tasks` for a change in Ready
- **THEN** it prints that the card is in Ready and has no tip

