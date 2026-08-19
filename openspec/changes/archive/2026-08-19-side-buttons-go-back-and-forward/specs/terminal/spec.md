## ADDED Requirements

### Requirement: Only the middle button is forwarded as the middle button

The terminal SHALL read which button an `otherMouse` event carries and SHALL
forward only the middle one to the program. macOS raises those events for button
2 — the middle — and for 3 and 4, the side buttons; all three were encoded as
`.middle`, which is button 1 on the wire, so a side button reached the program as
a middle click. Middle click in a terminal is commonly paste, which makes a side
button press over the terminal capable of putting the selection into the shell.

**A button the terminal does not act on SHALL travel up rather than being
consumed.** Both paths returned without calling `super` — the one for a program
that is not tracking the mouse, and the one where the forward is declined — so
these events stopped at the terminal and nothing above it could ever see them.
That is what made the side buttons do nothing over the pane people have open
most.

The middle button's own behaviour SHALL be unchanged, including that a program
which is not tracking the mouse is not sent one.

Side buttons SHALL NOT be forwarded to the program at all: the emulator encodes
left, middle, right, none and the two scroll codes, and has no code for them.

#### Scenario: a side button over a program that tracks the mouse

- **GIVEN** a terminal running a program that has asked for mouse events
- **WHEN** a side button is pressed
- **THEN** the program receives nothing
- **AND** the event reaches the window

#### Scenario: the middle button still pastes where it did

- **GIVEN** the same program
- **WHEN** the middle button is pressed
- **THEN** it is forwarded as the middle button, exactly as before

#### Scenario: a program that is not tracking the mouse

- **WHEN** the middle button is pressed
- **THEN** nothing is sent, as before
