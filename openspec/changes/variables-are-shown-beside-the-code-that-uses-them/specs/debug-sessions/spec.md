## ADDED Requirements

### Requirement: A stopped frame shows its variables beside the code that names them

While a session is stopped, the editor SHALL draw the value of a variable at the
end of each line that names it, in the file the selected frame belongs to.

The values SHALL be the ones the adapter has already returned for that frame —
its scopes and their variables — and **nothing further SHALL be asked of the
adapter to draw them**. No `evaluate`, and no request per line: in several
languages evaluating runs the debuggee's own code, and drawing a hint must not
be able to change the program being debugged.

A name SHALL match only as a whole token, so that `count` is not found inside
`counter` or `account`.

Values SHALL be drawn only for lines at or above the line execution stopped at.
Below it a value is either left over from a previous pass or not yet assigned,
and it would be drawn in the same grey as one that is true.

Each hint SHALL be one line, truncated where the value is long, and SHALL be
drawn after the last character of the line so that no code moves. Where a line
names several variables in scope they SHALL appear in the order they occur on
the line.

Nothing SHALL be drawn, and nothing computed, while no session is stopped.

#### Scenario: stopped at a breakpoint

- **GIVEN** a session stopped in a file that is open
- **WHEN** the editor draws that file
- **THEN** each line at or above the stopped line that names a variable of the
  selected frame shows that variable's value at its end

#### Scenario: another file, and another frame

- **GIVEN** the same stop, with a second file open that the frame is not in
- **THEN** that file shows no values
- **AND** selecting a different frame in the stack moves the values to that
  frame's file and its own variables

#### Scenario: a name that is part of a longer one

- **GIVEN** a frame with a variable named `count`
- **WHEN** a line reads `accountTotal = counter + 1`
- **THEN** nothing is drawn for it

#### Scenario: nothing is running

- **GIVEN** a session that has resumed, ended, or never started
- **THEN** no values are drawn, and none are worked out

#### Scenario: a value too large to sit on a line

- **GIVEN** a variable whose value is a page of text, or has newlines in it
- **THEN** what is drawn is a single truncated line
- **AND** the whole value is still readable in the variables tree
