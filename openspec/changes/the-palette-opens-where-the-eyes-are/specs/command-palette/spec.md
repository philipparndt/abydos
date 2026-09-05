## ADDED Requirements

### Requirement: A key opens the palette over the window that answered it

The palette SHALL open, when ⇧⌘P is pressed, in a window of its own centred
horizontally on the window whose menu answered the key and near that window's
top edge, as the running-sessions list opened by ⇧⌘A already does, and SHALL
be a child of that window so that it follows it and stays above it. It SHALL
be kept inside that window's frame, so a window narrower than the list is not
given a list hanging off both its edges.

#### Scenario: the key opens it in the middle

- **WHEN** ⇧⌘P is pressed
- **THEN** the palette appears centred horizontally on the window that answered the key, near its top edge

#### Scenario: it follows the window it belongs to

- **GIVEN** the palette opened by the key
- **WHEN** that window is moved
- **THEN** the palette moves with it and stays above it

#### Scenario: a narrow window

- **GIVEN** a window narrower than the palette wants to be
- **WHEN** ⇧⌘P is pressed
- **THEN** the palette stays inside that window's frame

### Requirement: A control that is clicked keeps the palette at itself

The palette SHALL stay anchored to the control that was clicked when it is
opened by a click — the project pill, the branch pill, the run control — and
SHALL NOT move to the middle of the window: a list opened from a control is
about that control, and the pointer is already there.

#### Scenario: clicking the project pill

- **WHEN** the project pill is clicked
- **THEN** the list opens anchored to the pill, as it does today

#### Scenario: clicking the run control

- **WHEN** the run control's chevron is clicked
- **THEN** the run list opens anchored to that control

### Requirement: The palette a key opened is the same list, and closes the same ways

The palette SHALL show the same rows, ranking, filter field, arrow keys, ⏎ and
Escape however it was opened, being one controller in two windows. Escape,
⇧⌘P pressed again, and the palette losing the keyboard SHALL each close it.

#### Scenario: the same list either way

- **WHEN** the palette is opened by the key rather than by the pill
- **THEN** the rows, their ranking and the filter behave as they do from the pill

#### Scenario: the key closes it again

- **GIVEN** the palette opened by ⇧⌘P
- **WHEN** ⇧⌘P is pressed again
- **THEN** it closes

#### Scenario: clicking away closes it

- **GIVEN** the palette opened by ⇧⌘P
- **WHEN** the window behind it is clicked
- **THEN** it closes
