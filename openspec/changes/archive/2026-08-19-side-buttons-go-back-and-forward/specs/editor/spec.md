## ADDED Requirements

### Requirement: The side buttons go back and forward

A mouse's side buttons SHALL move through the navigation history — button 3 back,
button 4 forward — the same history ⌘[ and ⌘] move through, with the same rules
about when a step is possible and the same handling of a file deleted since.

They SHALL work wherever the pointer is in the window: over the editor, the tree,
the panes and the terminal. The window handles them, so no view has to opt in,
and a view that wants a side button for something of its own can still take it.

**They SHALL act on release rather than on press.** A navigation changes what is
on screen, and a button held while the hand is still deciding should not have
moved anything. The press SHALL be consumed so that nothing else sees a stray
one.

Where there is nowhere to go — no earlier place in the history, or no later one —
the button SHALL do nothing, which is the answer the menu items already give by
being disabled.

#### Scenario: back over the editor

- **GIVEN** somewhere visited earlier in this window
- **WHEN** the back side button is pressed and released over the editor
- **THEN** the editor returns to it, as ⌘[ would

#### Scenario: forward again

- **GIVEN** a step back just taken
- **WHEN** the forward side button is used
- **THEN** the editor returns to where it was

#### Scenario: over the terminal

- **WHEN** the back side button is used with the pointer over a terminal
- **THEN** the editor goes back, and nothing is sent to the terminal program

#### Scenario: nowhere to go

- **GIVEN** a window with nothing earlier in its history
- **WHEN** the back side button is used
- **THEN** nothing happens
