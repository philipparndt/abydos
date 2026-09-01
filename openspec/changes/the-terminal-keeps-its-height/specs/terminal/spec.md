# Terminal — delta

## ADDED Requirements

### Requirement: The panel keeps the height it was given

The terminal panel SHALL keep its height when the window's width changes, and
SHALL be left at the height it was asked for when it is rounded down to whole
terminal rows.

Rounding to whole rows SHALL be a fixed point: applying it once SHALL leave
nothing more to round. A `NSSplitView` gives its second subview
`total − position − dividerThickness`, so a divider position computed without
the thickness leaves the panel a point short of what was wanted, the terminal's
usable height a point short of whole rows, and a remainder of nearly a whole row
for the next pass to take off again. Widening a window posts one resize
notification after another, and the panel lost a row to each of them until it
reached its floor.

A resize in which the split's height did not change SHALL NOT move the divider.

#### Scenario: widening the window

- **GIVEN** a panel at some height
- **WHEN** the window is made wider without changing its height
- **THEN** the panel still has that height

#### Scenario: rounding to whole rows settles

- **GIVEN** a panel whose terminal has part of a row left over
- **WHEN** the rounding is applied
- **THEN** the panel is the height that was asked for, and asking again says
  there is nothing to round
