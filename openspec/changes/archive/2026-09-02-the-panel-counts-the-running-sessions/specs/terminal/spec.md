## MODIFIED Requirements

### Requirement: The panel's own controls are drawn on a ground of their own

The panel's controls SHALL be drawn on an opaque ground, so that a tab running
under them is hidden rather than showing through.

The tabs of a strip are laid out from its leading edge at whatever width each
name needs, and the controls — the running-sessions pill, the session tag,
follow, maximise, hide — are placed backwards from its trailing edge. With
enough tabs open the two meet: with a dozen terminals open the session tag was a
translucent pill with a tab's name legible underneath it and the glyphs
overlapping the names either side. This is the editor tab bar's own settled
answer to the same collision — a tab's last few characters matter less than the
controls staying readable and reachable.

The running-sessions pill is the leftmost of the controls and so the first the
tabs meet. It SHALL take no room when it is not drawn, so a panel with no
running session gives the tabs what the pill would have had.

A tab hidden this way SHALL still be reachable, which is the other half and is
covered by the tab-overflow capability.

#### Scenario: a strip with more tabs than room

- **GIVEN** a panel strip whose tabs reach the trailing edge
- **WHEN** it is drawn
- **THEN** the controls are legible against their own ground
- **AND** no tab name is drawn through them

#### Scenario: a strip with more tabs than room and sessions running

- **GIVEN** a panel strip whose tabs reach the trailing edge
- **AND** a running session on the machine, so the pill is drawn
- **WHEN** it is drawn
- **THEN** the pill's counts are legible against their own ground
- **AND** the tab that reached it is hidden under it, not drawn through it

#### Scenario: nothing running

- **GIVEN** no running session on the machine
- **WHEN** the strip is laid out
- **THEN** no room is reserved for the pill, and the tabs run to the session tag
