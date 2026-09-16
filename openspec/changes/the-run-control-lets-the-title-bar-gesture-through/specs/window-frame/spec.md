# window-frame Specification

## ADDED Requirements

### Requirement: The strip's controls are no wider than what they do

A control in the title strip SHALL take only the room for the parts it acts
on when pressed. Anything the strip shows that is read rather than pressed —
the message about the last run — SHALL be drawn on the title bar itself, not
inside a toolbar item, so that a double-click on it or beside it zooms the
window as a double-click between the pills and the buttons does.

**Reported 2026-09-16 on 0.21.1.** The run control reserved room beside the
scheme well for the status of the last run, and a double-click there did
nothing, while one between the pills and the buttons zoomed. A narrow window
moves the capsule and the pills into the overflow menu before the run control,
leaving a strip that was all run control — and so a window that could not be
zoomed from its title bar at all. Forwarding the press, the release and the
drags from the control changed nothing, and neither did declaring the view
movable: measured with two builds side by side, the gesture works through the
toolbar's flexible space and never through a custom item, whatever the item
does with the events. So the room had to stop being the item's.

#### Scenario: To the right of the run buttons

- **GIVEN** a window whose title strip shows the run control
- **WHEN** the room to the right of the scheme well, or to the left of the
  buttons, is double-clicked as a mouse does it — press, release, press,
  release
- **THEN** the window is zoomed, once, and stays zoomed, exactly as it does
  from the room between the pills and the buttons

#### Scenario: A window too narrow for the capsule

- **GIVEN** a window narrowed until the capsule and the pills no longer fit
  beside the run control
- **WHEN** it is looked at
- **THEN** the capsule and the pills are folded away by the title bar, not put
  into a toolbar overflow menu, and the run control keeps the trailing edge
  with free strip beside it
- **WHEN** that free strip is double-clicked
- **THEN** the window is zoomed

#### Scenario: A window with less room than the capsule's maximum

- **GIVEN** a window with room for the capsule but not at its full width
- **WHEN** it is looked at
- **THEN** the capsule is shown at the room there is, its names shortened to
  fit, and the strip beside the run control is still free

#### Scenario: A status message beside the buttons

- **GIVEN** the message of the last run showing left of the buttons
- **WHEN** the message's text is double-clicked, away from the cross that
  clears it
- **THEN** the window is zoomed and the message is still there
- **AND** a single click on the cross still clears the message and zooms
  nothing

#### Scenario: A message arrives

- **GIVEN** a run that has just ended
- **WHEN** its message appears
- **THEN** the play and debug buttons and the scheme well are where they were

#### Scenario: The buttons are still buttons

- **WHEN** play, debug, the chevron or the scheme well is pressed
- **THEN** it does what it did before, and the window's frame does not change
