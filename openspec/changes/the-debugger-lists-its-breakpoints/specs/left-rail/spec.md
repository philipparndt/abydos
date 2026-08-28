# left-rail

## ADDED Requirements

### Requirement: A rail button opens its pane and asks nothing else

A button in the bottom group SHALL open the pane it is the button for, and SHALL
NOT ask what to put in it. The rail says which pane is in front and puts one in
front; it is not where work is started.

The debug button did not keep this. With nothing running there was no debug pane
to open — the pane was built only when a session started it — so pressing the
ladybird popped a menu of ways to start a session instead: Debug Go Package,
Debug Executable…, Attach to Process…. One button in a group of four behaved
unlike the other three, and the question it asked belongs to the run control,
which is the thing in the window whose subject is starting programs.

#### Scenario: the debug button with nothing running

- **GIVEN** no debug session
- **WHEN** the debug button is pressed
- **THEN** the debug pane is opened, showing its breakpoints
- **AND** no menu appears

#### Scenario: the debug button with a session running

- **GIVEN** a debug session running with the panel closed
- **WHEN** the debug button is pressed
- **THEN** the panel opens with the debug pane in front, as it does today

#### Scenario: the button is not where a session is started

- **GIVEN** any project, Go or otherwise
- **THEN** the rail offers no way to launch a program, debug an executable or
  attach to a process
