## ADDED Requirements

### Requirement: A glyph that reaches past its cell is drawn whole

The pane SHALL draw a glyph that reaches past its cell whole, under either
renderer, whatever the cell after it holds; and a cell's background colour SHALL
stop at the cell's own edge.

A glyph may be wider than its cell: a descender or an accent by a little, a
symbol from a fallback font by nearly a cell — swift-testing's pass and fail
marks are 13.7 points wide at a 13-point size against a 7.8-point cell. Counting
it two columns would misplace everything after it, which tmux and Ghostty do not
do; so it spills, and what it spills into must not be painted over it
afterwards.

#### Scenario: swift-testing's marks

- **GIVEN** a pane drawn by the GPU renderer showing `􀟈  Test one`
- **WHEN** the drawable is captured
- **THEN** the diamond is whole, both halves, with the two spaces after it

#### Scenario: a coloured cell beside a plain one

- **GIVEN** a cell with a coloured background whose glyph leans into the plain cell to its right
- **WHEN** the pane is drawn
- **THEN** the colour ends at the cell's edge and the glyph's overhang shows the plain cell's colour around it
