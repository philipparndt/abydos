# starting-a-debug-session

## ADDED Requirements

### Requirement: One control asks what to debug, and it is the titlebar's

The ways of starting a debug session SHALL be offered from the debug button in
the window's run control — the ladybird beside the play button — and from the Run
menu. No pane, and no button whose job is to show a pane, SHALL ask.

The run control is already the thing whose subject is starting: a play button, a
ladybird, a chosen configuration, and a chevron whose menu holds the other
answers — Debug, Profile, Run with Coverage. "Attach to Process…" is another
answer to the same question and belongs beside them.

Pressing the ladybird itself SHALL debug the selected configuration, which is
what it does today and what the ⌃D it carries means.

#### Scenario: the menu beside the ladybird

- **WHEN** the chevron beside the ladybird is pressed
- **THEN** the menu offers Debug, Debug Executable…, and Attach to Process…,
  along with Profile and Run with Coverage

#### Scenario: the ladybird itself

- **WHEN** the ladybird is pressed
- **THEN** the selected configuration is debugged, with nothing asked

### Requirement: A way of starting that the project cannot use is not offered

Debugging a Go package SHALL be offered where the project is a Go one — a module
at its root, or one below it — and SHALL NOT be offered otherwise.

The rail's button used to start a Go session outright, which in a project that is
not Go produced an error about a missing `go.mod`: an answer to a question nobody
asked. Offering it only where it can work is the same rule, kept a step earlier.

#### Scenario: a Go project

- **GIVEN** a project with a `go.mod` at its root or in a directory below it
- **THEN** the menu offers Debug Go Package

#### Scenario: a project that is not Go

- **GIVEN** a project with no Go module anywhere in it
- **THEN** the menu does not offer Debug Go Package

### Requirement: Attaching lists what is running and says when nothing is

Attach to Process SHALL list the processes running on the machine, filterable by
name, and SHALL start a session on the one chosen, with the debug adapter that
suits the program at that path.

Launching cannot cover a server that is already up, or a process that only
misbehaves after an hour of work.

Where there is nothing to attach to, that SHALL be said as itself, rather than by
opening an empty picker.

#### Scenario: choosing a process

- **WHEN** a process is chosen from the picker
- **THEN** a session attaches to it, carrying the breakpoints the project has

#### Scenario: nothing is running

- **GIVEN** no processes were found
- **THEN** it is reported that there is nothing to attach to, and no picker
  appears

### Requirement: A debugger adapter that is not installed is named

Where the adapter a chosen program needs is not installed, that SHALL be reported
by name, with what to do about it, rather than the session failing to start with
nothing said.

#### Scenario: no adapter for the chosen program

- **WHEN** a program is chosen whose adapter is not installed
- **THEN** the adapter is named, along with how to install it, and no session
  starts
