<!-- What this item changes about `terminal`. Folded into
     .abydos/backlog/spec/terminal.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A pane does not inherit a tmux socket path that could not exist
       A pane says how large one of its cells is, and says so again when that changes
       A picture placed where there is not room for it makes the room
       A pane shows what a command printed even if the command has already finished
       A pane can be emulated by libghostty-vt instead of by our own emulator
       An engine says what it cannot do, and the missing parts refuse rather than guess
       A picture drawn with unicode placeholders is shown under either engine
       A pane draws at the display's rate while a program keeps up, and does not replay a backlog
-->

## ADDED Requirement: Either engine names the rows that changed, and neither says "all of them" unless they did

A pane redraws the rows a program touched rather than the screen, and that is
the difference between a prompt rewritten under a keystroke costing one row and
costing eleven thousand cells. So an engine's answer to "what changed since you
were last asked" is the rows, in the numbering the pane scrolls through, and
**both engines answer it the same way**: our own tracks it as it parses, and
libghostty-vt is asked for the per-row dirtiness it keeps inside its render
state.

Three things still are the whole document, and they are the cases where that is
the truth rather than a shrug:

- A line falling out of the top of history, because that renumbers every row
  below it. Anything remembering what it worked out about a row keeps it under a
  number, and the moment those numbers move is the moment nothing may be kept.
- A program taking the screen over, or handing it back, or resetting the
  terminal. The rows are the same rows and every one of them means a different
  line.
- Anything the engine cannot narrow down — a palette change, a viewport that
  moved. An engine that reports too much draws more than it needed to; one that
  reports too little leaves last minute's text on the screen, and only the second
  is a fault somebody has to notice.

Taking the answer clears it, and a frame drawn for a reason of its own — a
cursor blinking, a window coming forward — is told nothing changed rather than
being handed the rows from the frame before.

### Scenario: a shell rewrites its prompt line where it already is

- **Given** a pane with a screenful of output and history behind it, under either
  engine
- **When** the program moves the cursor up, clears that line and writes it again
- **Then** the pane is told one row changed
- **And** the rows it had already worked out for every other line are kept

### Scenario: a line falls out of the top of history

- **Given** a pane whose scrollback is full, under either engine
- **When** enough output arrives to push a line off the top for good
- **Then** the pane is told the whole document changed

### Scenario: a program takes the screen over

- **Given** a pane running a shell, under either engine
- **When** a full-screen program takes the terminal over, and again when it hands
  it back
- **Then** the pane is told the whole document changed each time

### Scenario: a frame with nothing new behind it

- **Given** a pane that has just been drawn, under either engine
- **When** it is asked again with no output having arrived in between
- **Then** it is told that nothing changed

## ADDED Requirement: How big a terminal is and how much history it has are cheap questions, and asking them does not copy the screen

The pane asks the engine two different kinds of question. **What is on the rows**
is a snapshot: it has to survive whatever the program writes next, so for an
engine that keeps its grid on the far side of a library boundary it means copying
the cells out. **How tall is the document, how far down does the active grid
start, how many lines have gone for good** are numbers every engine already has
to hand.

Those are asked separately, because the pane asks the second kind on the path
that output arrives on — once per delivery, thousands of times a second — and
answering them with a snapshot made libghostty-vt forty times slower in the app
than our own engine while being the faster parser of the two. A snapshot is for
drawing a frame. Nothing on the parse path takes one.

### Scenario: output arriving while a selection is held

- **Given** a pane with a selection in it, emulated by libghostty-vt, receiving
  output as fast as it can be read
- **When** each delivery is parsed
- **Then** the pane asks only how many lines have been discarded, so that the
  selection can follow them
- **And** no copy of the screen is made for it
