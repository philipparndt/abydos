# version-control

## ADDED Requirements

### Requirement: The numbers on a changes row are drawn in columns

The added count, the removed count and a folder's file tally SHALL each be drawn
right-aligned on one x for the whole of that side, not on the trailing edge of
their own row.

Every row put its text hard against the trailing inset, so a folder — which has
a tally after its counts — pushed its `+69 −16` left by the width of that tally
and the file under it did not. Reading down a nested tree, the plus signs
stepped in and out by a digit at every level, which is the one thing a column of
numbers exists not to do.

The columns SHALL be as wide as the widest value on that side, so a `+1234`
somewhere in the tree does not overlap the row above it, and SHALL be measured
once per reload rather than once per row.

**The name gives way, as it already did.** A long path and `+1234 −567` do not
both fit in a sidebar, and of the two the name can be cut and still be
recognised. A file row now reserves the tally column it never draws in, which is
what alignment costs.

#### Scenario: a folder and the file under it

- **GIVEN** a folder whose only changed file is `BranchesPane.swift`
- **THEN** the folder's `+98` and the file's `+95` are drawn on the same x
- **AND** so are their removed counts

#### Scenario: a pane too narrow for both

- **GIVEN** the pane at 250 points and a deeply nested path
- **THEN** the columns hold and the name is what is cut
