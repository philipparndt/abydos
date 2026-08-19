## ADDED Requirements

### Requirement: Find belongs to the tab it searched

The find bar's state SHALL belong to the tab it was opened in — whether it is
showing, what is in it, which options are set, the matches and which one is
current. A group holds many tabs and one bar; the bar shows the state of the tab
in front, and shows the previous one again when that tab is.

This is the pattern the rest of the editor already follows and says it follows:
each tab owns its own `CodeView`, so caret, selection, scroll offset and folds
survive a tab switch because they were never shared. Find was the exception.

**The matches SHALL NOT outlive the tab that produced them.** They are UTF-16
offsets into one document, and the view they are handed to sets a caret from
them. Offsets from one file reaching another file's view is the fault this
prevents, and it is not merely untidy: a match band is drawn at an offset the
text does not have, and the caret is set past an end that may not exist.

One bar, not one per tab. The bar is chrome for the group; only its contents
belong to the tab.

#### Scenario: find open in one tab

- **GIVEN** two files open in one group
- **WHEN** find is opened in the first and the second is selected
- **THEN** the second shows no find bar

#### Scenario: coming back to a tab that was searching

- **GIVEN** a tab with find open, a query typed and a match current
- **WHEN** another tab is selected and then that one again
- **THEN** the bar is showing, with the same query and options
- **AND** the same match is current

#### Scenario: stepping after a tab switch

- **GIVEN** a tab searched for a word that its file contains
- **WHEN** another tab is selected and the next match is asked for
- **THEN** nothing is stepped in the file that was not searched

#### Scenario: closing find

- **GIVEN** two tabs, both with find open
- **WHEN** find is closed in one
- **THEN** the other still has it open when it is selected

#### Scenario: a tab that is closed

- **GIVEN** a tab with find open and matches found
- **WHEN** the tab is closed
- **THEN** its find state goes with it

### Requirement: A search that found nothing says so in red

A search that found nothing SHALL say `No results` in red. The two states of the
bar that a person acts on differently — there are matches, there are none —
differed by one grey word in the corner, in the colour used for everything else
that is merely informational.

The red SHALL be the scheme's own, `gitConflict`, which is the red the bar
already reaches for. A colour of its own would need a scheme role of its own, and
a required role that a file lacks refuses the whole file — which would refuse
every scheme written before it existed.

**The query text itself is not the signal, and that is a finding rather than a
choice.** Colouring it was implemented and measured not to reach the screen: with
`field.textColor`, the field editor's `textColor` and the attributed string all
holding that red, a capture has the query at `(236, 235, 235)` over 1007 glyph
pixels with none of them reddish, beside a `No results` at `(212, 114, 112)`.
`NSSearchField` paints its text in a colour of its own. Owning it would mean
replacing the control and drawing the magnifier and the clear button by hand,
which is a larger change than this.

An empty query SHALL stay plain and say nothing. It has not found nothing; it has
not been asked.

#### Scenario: a query with no matches

- **WHEN** a query matches nothing in the file
- **THEN** `No results` is shown in red

#### Scenario: a query with matches

- **WHEN** a query matches
- **THEN** the count is shown, and nothing is red

#### Scenario: the query is cleared

- **GIVEN** a query that matched nothing
- **WHEN** it is deleted
- **THEN** nothing is red and nothing is said

### Requirement: A pattern that did not compile says so rather than reporting no results

A regex query that does not compile SHALL say that it is incomplete rather than
say `No results`. Nothing was searched, so "no results" is an answer to a
question that was never asked — and it is indistinguishable from a search that
ran and found nothing, which is a different thing to act on.

This is already the intent where the field is coloured: an unfinished regex is
marked invalid there "rather than reported as 'no results', which would read as a
wrong answer". The label a few pixels away then said `No results` anyway, because
an invalid pattern still reached the search and the search still returned
nothing. **Once red means both "found nothing" and "did not run", the words are
what tell them apart**, so they have to differ.

A query that does not compile SHALL NOT run a search, and SHALL NOT discard the
matches of the last query that did.

#### Scenario: half a pattern typed

- **GIVEN** find in regex mode
- **WHEN** `(` is typed and no more
- **THEN** the query is red and the bar says the pattern is incomplete
- **AND** it does not say `No results`

#### Scenario: the pattern is finished

- **GIVEN** an incomplete pattern in the bar
- **WHEN** the rest of it is typed and it matches
- **THEN** the query is plain and the count is shown

#### Scenario: the same words are not used for two situations

- **WHEN** the bar says `No results`
- **THEN** a search ran and returned nothing
