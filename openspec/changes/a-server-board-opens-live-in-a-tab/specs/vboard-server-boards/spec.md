## ADDED Requirements

### Requirement: The boards on the server can be listed and one opened in a tab

File ▸ Open vboard Board… SHALL list the boards on the server named in the
`vboard.server` setting that the server's own board lookup returns to the
account in use, filtered by the text typed, and SHALL open the chosen board in a
tab. Private boards SHALL NOT be listed. The command SHALL be unavailable when no
usable server is named, and on a driven run.

#### Scenario: picking a board

- **GIVEN** `vboard.server` set to a reachable vboard server with boards
  "Sprint 42 retro" and "Architecture map"
- **WHEN** somebody chooses File ▸ Open vboard Board… and types "retro"
- **THEN** the list shows "Sprint 42 retro" and not "Architecture map", and
  choosing it opens a tab named "Sprint 42 retro" showing that board

#### Scenario: the same board twice

- **GIVEN** a board already open in a tab from the picker
- **WHEN** the same board is chosen again
- **THEN** the existing tab comes to the front and no second tab is made

### Requirement: A board opened from the server is the live board

A tab opened from the server's board list SHALL show the board itself, not a
copy: no file SHALL be made, the tab SHALL never show an edited dot or ask to
save, and closing it SHALL NOT delete, lease or otherwise change the board on
the server.

#### Scenario: an edit from the tab

- **GIVEN** a server board open in a tab and the same board open in a browser
- **WHEN** a sticky is added in the tab
- **THEN** the browser shows it, and the tab has no edited dot

#### Scenario: closing the tab

- **WHEN** the tab is closed
- **THEN** the board is still on the server with everything on it

### Requirement: A copy of a server board can be saved as a file

File ▸ Save a Copy of the Board… SHALL be available while a server board's tab
is in front, and SHALL write the board's export as a `.vboard` file at the place
chosen, through a temporary file and a rename.

#### Scenario: saving a copy

- **GIVEN** a server board open in a tab
- **WHEN** a copy is saved into the project
- **THEN** a `.vboard` file appears there that opens as a board with the same
  items
