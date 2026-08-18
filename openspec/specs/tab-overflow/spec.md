# tab-overflow Specification

## Purpose
TBD - created by archiving change a-tab-that-does-not-fit-is-still-reachable. Update Purpose after archive.
## Requirements
### Requirement: Every open tab is reachable however many there are

A tab strip SHALL offer a way to select any tab it holds, whatever the width of
the window. Today both strips lay tabs out left to right with no bound and
neither takes a `scrollWheel`, so a tab past the trailing edge can be reached
only by widening the window or closing the tabs in front of it — and for the
panel's strip there is not even a keyboard route, since ⌘] and ⌘[ move between
editor tabs.

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

### Requirement: Hidden means covered, not merely past the edge

A tab SHALL count as visible only where the whole of it is in front of the
opaque ground the trailing controls are drawn on. Tabs run underneath those
controls, which is the editor tab bar's own settled answer — the control staying
readable and reachable matters more than a tab's last few characters.

A tab half under the session tag is not a target: it is a tab somebody clicks and
misses.

#### Scenario: a tab partly under the panel's controls

- **GIVEN** a tab whose trailing half is behind the session tag
- **WHEN** the hidden tabs are counted
- **THEN** it is one of them

### Requirement: The active tab is one that can be seen

The strip SHALL keep the active tab wholly visible, moving the run of tabs by the
least that achieves it. Selecting a tab that then stays hidden is the same fault
with a click in front of it.

**That is the only reason the run moves.** Nothing else scrolls it: not the
wheel, not a drag, not a tab being added elsewhere, and where it starts is not
remembered between launches.

Where the run has moved, tabs may be hidden before it as well as after it. Both
SHALL be counted and both SHALL be listed, in tab order, so the ones behind come
first.

#### Scenario: activating the last of many

- **GIVEN** a strip showing the first ten of sixteen tabs
- **WHEN** the sixteenth is chosen from the overflow list
- **THEN** it is wholly visible
- **AND** the tabs now hidden before it are counted with those after it

#### Scenario: nothing else moves the run

- **GIVEN** a strip with hidden tabs and the active one visible
- **WHEN** the pointer is scrolled over the strip
- **THEN** nothing moves

### Requirement: The strip survives its list being rebuilt underneath it

Where the run of tabs has moved, the strip SHALL remember which tab it starts at
by identity and not by position. The panel's strip mirrors tmux's window list and
is rebuilt whenever that is re-read, which is several times a second while a
session is watched: a window closed in another client shifts every index after
it, and a window moved keeps none.

Where the tab it started at is gone, the strip SHALL go back to starting at the
first — the state it is in when nothing has moved.

#### Scenario: a tmux window closed elsewhere

- **GIVEN** a mirrored strip whose run starts at the fourth window
- **WHEN** that window is closed by another client
- **THEN** the strip starts at the first again, rather than at whatever is now
  fourth

