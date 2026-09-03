## ADDED Requirements

### Requirement: A folded merge draws none of its branch's lanes
When a merge is folded, the graph SHALL be laid out over the rows that are drawn, so that no lane belonging to a hidden commit appears. No line SHALL be drawn that has no visible commit to start from.

#### Scenario: Folding a merge with a branch under it
- **WHEN** a merge is folded on the log page
- **THEN** the lanes of the branch it brought in are gone from every row below, and every line still drawn begins at a commit that is on screen

#### Scenario: Unfolding puts it back
- **WHEN** the same merge is unfolded again
- **THEN** the graph is the one that was there before it was folded
