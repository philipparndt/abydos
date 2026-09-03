## ADDED Requirements

### Requirement: The list answers the arrows

The popover SHALL be navigable from the keyboard without the mouse: ↓ in the
filter field selects the first session still shown and gives the rows the
keyboard; ↓ and ↑ then move the selection between sessions, skipping the group
headers and the footer; and ⏎ opens the selected session, doing what a click on
its row does.

↑ from the first session SHALL return the keyboard to the filter field with the
caret at the end of what was typed, so narrowing and choosing are one movement
in each direction. Escape SHALL put the popover away, from the rows as from the
field.

The selected row SHALL be drawn in the palette's selection colour, and a row
under the pointer in the hover tint, so which row ⏎ will act on is never a
guess and the two questions are told apart. The selection SHALL be scrolled
into view, and SHALL be kept by the session's id across a reload — falling back
to the first row when that session has gone.

#### Scenario: Down out of the field

- **GIVEN** the popover open with the keyboard in the filter
- **WHEN** ↓ is pressed
- **THEN** the first session is selected, drawn as selected, and the rows have the keyboard

#### Scenario: Through the rows and into a session

- **GIVEN** a list of three sessions with the first selected
- **WHEN** ↓ is pressed twice and ⏎ once
- **THEN** the third session is opened, as clicking its row would

#### Scenario: The arrows skip what is not a session

- **GIVEN** two projects of one session each, so a header sits between the rows
- **WHEN** ↓ is pressed from the first session
- **THEN** the second session is selected, not the header

#### Scenario: Back up to the filter

- **GIVEN** the first session selected and `scr` in the filter
- **WHEN** ↑ is pressed
- **THEN** the filter has the keyboard, still reads `scr`, and the caret is at its end

#### Scenario: A reload under the selection

- **GIVEN** a selected session
- **WHEN** an event arrives and the list is rebuilt
- **THEN** the same session is still selected
