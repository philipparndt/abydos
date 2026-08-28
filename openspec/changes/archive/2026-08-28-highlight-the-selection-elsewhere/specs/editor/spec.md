# editor

## ADDED Requirements

### Requirement: A row states its precedence in the order it is painted

The bands drawn on a row SHALL be painted in an order that states which claim
wins where two cover the same pixels, and a band added later SHALL take a place
in that order rather than be layered where it is convenient.

The order is already a decision. The line background goes down first; the find
matches that are not current go under the selection; the text and the selection
follow; the current find match goes on **over** the selection. That last one is
item 0536: revealing a match selects it, so the two cover the same pixels, and
with the selection painted second the one match meant to be findable at a glance
measured 1.4 against the editor ground where it had been 5.6 — below the 2.2 of
every other match on the page. The strongest became the weakest.

A selection's occurrences are the third kind of band, and they take the depth the
non-current find matches have: over the line background, under the selection.
They never share a row with a find match, because find's matches win while find
is showing.

#### Scenario: an occurrence under a selection extended over it

- **GIVEN** a selection extended across another place its own text appears
- **THEN** the selection is drawn at full strength there

#### Scenario: the current find match is still the loudest

- **GIVEN** a file with find matches and a selection over the current one
- **THEN** the current match is drawn over the selection, as it is today, and no
  occurrence band is drawn anywhere on the page
