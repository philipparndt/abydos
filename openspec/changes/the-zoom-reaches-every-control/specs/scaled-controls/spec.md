## ADDED Requirements

### Requirement: A control's size follows the zoom at every step
Every control in the library SHALL take its font, its padding, its corner radius and its height from `Theme.current` at the scale in force, and SHALL do so at all nine zoom steps without an upper bound. No member of the library SHALL take its size from an AppKit `controlSize`, because that has a largest value and walls out at roughly 1.4×.

#### Scenario: The largest zoom
- **WHEN** the zoom is 2.0 and a library button is asked for its intrinsic height
- **THEN** the height is twice what the same button reports at 1.0, within rounding to whole points

#### Scenario: A bezel is never the source of a size
- **WHEN** any library member is drawn
- **THEN** its height comes from the theme's scaled metrics and not from `controlSize`, and its words are never larger than the shape around them

### Requirement: A control re-takes its metrics without being told
The library SHALL observe `.abydosSettingsChanged` on behalf of every live control it holds, so that a control is correct after a zoom or a palette change without the pane that owns it re-applying anything.

#### Scenario: A zoom while a pane is on screen
- **WHEN** the zoom changes while a pane holding library controls is visible
- **THEN** every control in that pane is at the new size on the next display pass, and no code in the pane was called to make it so

#### Scenario: A control that has gone away
- **WHEN** a control is released while the registry still holds a reference to it
- **THEN** the reference is weak, the control is deallocated, and the registry drops the empty box the next time it is walked

### Requirement: The library says which members are drawn and which are measured
The library SHALL have two kinds of member and SHALL state which kind each is: a *drawn* member paints itself and carries no system artwork; a *measured* member keeps an AppKit control for behaviour that is not worth reimplementing and is given its font and its height from the theme instead.

#### Scenario: A search field keeps its behaviour
- **WHEN** a library search field is used
- **THEN** it still offers the field editor, the cancel button and the search menu, and its height and font follow the zoom

#### Scenario: A new member is placed deliberately
- **WHEN** a control is added to the library
- **THEN** it is either drawn or measured, and which it is, is stated where it is defined
