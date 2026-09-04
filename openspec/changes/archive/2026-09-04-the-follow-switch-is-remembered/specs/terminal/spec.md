## ADDED Requirements

### Requirement: Following the terminal is remembered

Turning following on or off SHALL be remembered between sittings, whichever of
the two controls was used: the checkbox in the settings page and the switch on
the terminal panel write the same preference.

A window SHALL start from that preference, and SHALL adopt it again when the
preference itself changes while the window is open — but not when some other
preference changes, since following is a per-window switch afterwards and a
window must not lose its own answer because a font size moved.

#### Scenario: turned on from the panel, then quit

- **GIVEN** following turned on with the switch on the terminal panel
- **WHEN** the app is quit and started again
- **THEN** following is on

#### Scenario: ticked in the settings page while a window is open

- **WHEN** the preference is changed in the settings page
- **THEN** an open window follows it from that moment

#### Scenario: some other setting changes

- **GIVEN** a window whose own switch differs from the stored preference
- **WHEN** an unrelated setting is changed
- **THEN** the window keeps its own answer
