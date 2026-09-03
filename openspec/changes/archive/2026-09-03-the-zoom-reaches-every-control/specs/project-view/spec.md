## ADDED Requirements

### Requirement: The tree's background follows a palette change
The project tree's background SHALL be re-applied when the palette changes, so that the tree, the header above it and the pane around it are never in two different palettes at once.

#### Scenario: Going light
- **WHEN** the palette changes from dark to light while the tree is showing
- **THEN** the tree's background and the surface behind its rows are the new palette's, matching the header directly above them

#### Scenario: Presentation mode swaps the palette
- **WHEN** presentation mode is switched on or off and it carries a different palette
- **THEN** the tree follows it, in the same display pass as the rest of the window
