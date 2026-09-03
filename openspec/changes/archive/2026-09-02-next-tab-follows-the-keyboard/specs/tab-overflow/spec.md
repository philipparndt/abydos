## MODIFIED Requirements

### Requirement: Every open tab is reachable however many there are

A tab strip SHALL offer a way to select any tab it holds, whatever the width of
the window. Both strips lay tabs out left to right with no bound and neither
takes a `scrollWheel`, so a tab past the trailing edge could once be reached
only by widening the window or closing the tabs in front of it. The panel's
strip had no keyboard route either until ⌘⇧] and ⌘⇧[ learnt to follow the
keyboard, which the terminal capability describes; the control below is still
the way to a tab whose name cannot be seen.

Where a strip holds more tabs than it can show, it SHALL carry a control at its
trailing end that lists the ones that are not fully visible and selects the one
chosen. The control SHALL say how many those are: three hidden and eleven hidden
are different situations and a bare chevron says neither.

Where every tab fits, no control SHALL appear.

#### Scenario: sixteen terminals in a window that fits ten

- **GIVEN** a panel strip with sixteen tabs and room for ten
- **WHEN** the strip is drawn
- **THEN** a control at its trailing end says six are not shown
- **AND** opening it lists those six, in tab order

#### Scenario: choosing one that was hidden

- **GIVEN** that list
- **WHEN** one of them is chosen
- **THEN** it becomes the active tab
- **AND** it is fully visible in the strip

#### Scenario: a strip with room to spare

- **GIVEN** a strip whose tabs all fit
- **WHEN** it is drawn
- **THEN** there is no overflow control at all
