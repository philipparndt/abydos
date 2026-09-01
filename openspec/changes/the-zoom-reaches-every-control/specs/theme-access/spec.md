## ADDED Requirements

### Requirement: A value copied out of the theme is re-taken when the theme changes
A colour, a font or a metric read from `Theme.current` and stored — in a layer, in a control, in a constraint constant or in a row height — SHALL be re-read when the palette or the scale changes. A view that reads the theme inside its drawing satisfies this by repainting; a view that copies the value SHALL have a path that copies it again.

#### Scenario: A metric captured when a view was built
- **WHEN** a view stores a scaled metric at build time and the scale later changes
- **THEN** the stored metric is recomputed at the new scale before the view is next shown

#### Scenario: A colour copied into a control
- **WHEN** a control is given a colour from the palette and the palette later changes
- **THEN** the control is given the corresponding colour from the new palette
