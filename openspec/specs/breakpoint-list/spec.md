# Breakpoint list

## Purpose

Every breakpoint a project has, as a list in the debugger: where each one is,
what its line holds, whether it is on and what it waits for — and the debug
pane being openable with nothing running, which is what gives the list
somewhere to live.

## Requirements
### Requirement: Every breakpoint a project has is listed in one place

The debug pane SHALL show, on a tab of its own beside the call stack, every
breakpoint the project has: the file it is in, the line it is on, and the
condition it carries where there is one. The list SHALL be ordered by file and
then by line, so the same set is in the same order every time it is opened.

A breakpoint is drawn in the gutter of the file it is in and nowhere else, which
answers "is there one on this line" and never "where are they all". Six of them
across four files can presently be established only by opening four files, and
the app already has a verb about all of them at once — silence every breakpoint
but one — reachable only by right-clicking one of them in a gutter.

A file inside the project SHALL be named relative to its root, and a file outside
it — a dependency's source, a standard library — named in full, because that is
the part of the path that says which is which.

#### Scenario: breakpoints in three files

- **GIVEN** a project with two breakpoints in `main.go` and one in `serve.go`
- **WHEN** the Breakpoints tab is shown
- **THEN** three rows are listed, `main.go` before `serve.go`, and the two in
  `main.go` in line order

#### Scenario: a breakpoint outside the project

- **GIVEN** a breakpoint in a dependency's source, outside the project root
- **THEN** its row names the file by its full path, and it is listed with the rest

#### Scenario: nothing set

- **GIVEN** a project with no breakpoints
- **THEN** the tab says so in a sentence that names the way to make one, rather
  than showing an empty table

### Requirement: The debug pane opens with nothing running

The debug pane SHALL open whether or not a session is running, and SHALL show the
Breakpoints tab when there is none.

It could not: the pane was built around a session handed to it, and the only
thing that ever built one was a session starting. Pressing the rail's ladybird
with nothing running therefore had nothing to open, which is why it asked how to
start a session instead.

A pane with no session SHALL show its stepping verbs disabled rather than absent,
and SHALL show nothing where the stack, the variables and the goroutines go —
the same nothing a session that has ended leaves.

#### Scenario: opened with nothing running

- **GIVEN** no debug session
- **WHEN** the debug pane is opened
- **THEN** it appears with the Breakpoints tab showing, the stepping verbs
  disabled, and no stack, variables or goroutines

#### Scenario: a session is running

- **GIVEN** a program stopped at a breakpoint
- **WHEN** the debug pane is brought forward
- **THEN** it shows the call stack, as it does today

#### Scenario: a session starts while the empty pane is open

- **GIVEN** the debug pane open on its Breakpoints tab with nothing running
- **WHEN** a debug session is started
- **THEN** the pane shows that session, on the Stack tab

### Requirement: A row carries the code its line holds

A row SHALL show the code on the line the breakpoint is on, read when the row is
drawn rather than remembered.

A file and a line number say where to look and not what is there, and the text is
the whole difference between recognising a breakpoint and having to open the file
to find out which one it is. It is read from the editor's document when the file
is open — so an unsaved edit shows the line as it is now — and from the file
otherwise. It SHALL NOT be written to the session file: text restored from disk
is text that was true when the app last closed, and a line of code that is
confidently wrong is worse than a row that shows only where it is.

#### Scenario: the file is open with unsaved changes

- **GIVEN** a breakpoint on a line somebody has just edited without saving
- **THEN** its row shows the line as it now reads in the editor

#### Scenario: the file is not open

- **GIVEN** a breakpoint in a file no editor has open
- **THEN** its row shows the line as the file on disk has it

#### Scenario: the file has gone

- **GIVEN** a breakpoint in a file that has been deleted or renamed
- **THEN** its row shows the file and the line, with no code beside them, and
  nothing is reported as an error

### Requirement: A breakpoint can be worked from its row

Every verb the gutter offers for a breakpoint SHALL be reachable from its row:
going to it, turning it off and on, deleting it, giving it a condition, and
silencing every other one.

Each SHALL act through the same path the gutter takes, so that a running session
is told and the change is written down — a list with verbs of its own would be a
second owner of a set that has one.

#### Scenario: going to one

- **WHEN** a row is opened
- **THEN** the editor shows that file at that line

#### Scenario: turning one off

- **WHEN** a row is turned off
- **THEN** its gutter marker is hollow, the adapter is told when a session is
  running, and the change survives the project being closed and opened

#### Scenario: deleting one

- **WHEN** a row is deleted
- **THEN** the breakpoint is gone from the gutter and from the list

#### Scenario: giving one a condition

- **WHEN** a row is asked for its options
- **THEN** the same sheet the gutter opens appears, and the condition it is given
  shows on the row

### Requirement: The list follows the set rather than holding a copy

The list SHALL be rebuilt from whoever holds the breakpoints whenever that set
changes, from anywhere: the gutter, the options sheet, a session verifying one,
or a project being opened.

Two owners of one set is how a breakpoint deleted in one place comes back from
the other.

#### Scenario: a breakpoint set in the gutter

- **GIVEN** the Breakpoints tab showing
- **WHEN** a breakpoint is set by clicking a gutter
- **THEN** a row for it appears without the tab being reopened

#### Scenario: the adapter verifies one

- **GIVEN** the list showing breakpoints restored from the session file, drawn as
  unverified
- **WHEN** a session starts and the adapter confirms them
- **THEN** the rows say so, the same way the gutter does

#### Scenario: another project is opened

- **GIVEN** the Breakpoints tab showing one project's breakpoints
- **WHEN** the window switches to another project
- **THEN** the list is that project's, and holds none of the first project's
