## ADDED Requirements

### Requirement: A key opens the list of running sessions

The application SHALL offer the list of running Claude sessions on a keyboard
shortcut of ⇧⌘A, from a menu item in the Agent menu, whether or not the
terminal panel that carries the sessions pill is open.

#### Scenario: The key opens the list with the panel closed

- **WHEN** the terminal panel is closed and ⇧⌘A is pressed
- **THEN** the list of running sessions opens
- **AND** it opens whether or not any session is running, so that the answer
  "nothing is running" is one somebody can ask for
- **AND** with nothing running the foot says so and says nothing else, since
  the note about what a click copies has no row to be about

#### Scenario: The list opens over the window that answered the key

- **WHEN** the list is opened by the key
- **THEN** it appears centred horizontally on the window whose menu answered
  the key, near its top edge
- **AND** it is a child of that window, so it follows it and stays above it

#### Scenario: The key and the pill open the same list

- **WHEN** the list is opened by the key rather than by the pill
- **THEN** the filter field, the rows, the arrow keys, ⏎ and Escape behave as
  they do in the popover
- **AND** choosing a row does what choosing it in the popover does

#### Scenario: One list at a time

- **WHEN** the list is open by one route and is opened by the other
- **THEN** the first is put away, so the list is never on screen twice

#### Scenario: Escape and a click elsewhere put it away

- **WHEN** the list opened by the key has the keyboard and Escape is pressed
- **THEN** it closes and the keyboard returns to the window
- **WHEN** another window is clicked while it is open
- **THEN** it closes

### Requirement: The popover says which key opens the list

The popover MUST show the shortcut that opens the list, dimmed, at the trailing
edge of its filter row, so that somebody who reached the list by clicking the
pill can see the key that reaches it next time.

#### Scenario: The shortcut is drawn beside the filter

- **WHEN** the popover is open
- **THEN** `⇧⌘A` is shown at the trailing edge of the row holding the filter
  field
- **AND** it is drawn in the dimmed colour used for text that is not the
  content, so it does not compete with the sessions

#### Scenario: The palette does not repeat the key

- **WHEN** the list was opened by the key
- **THEN** the shortcut is not shown, because it has just been used
