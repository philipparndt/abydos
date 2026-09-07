## ADDED Requirements

### Requirement: Soft wrap cuts at words

With soft wrap on, a visual row SHALL end after the last whitespace on it that
follows a word, so the next row begins with a whole word and the whitespace
stays at the end of the row above. Whitespace at the start of a row SHALL NOT
be a place to cut. A word longer than the row SHALL be cut at the edge. The
row count, the units on each row and the row an offset is on SHALL come from
the same cuts.

Prose read in the editor was broken mid-word at the column edge, which
destroys the reading flow soft wrap exists to keep.

#### Scenario: a sentence

- **GIVEN** `the quick brown fox jumps` wrapped at ten columns
- **THEN** the rows are `the quick `, `brown fox ` and `jumps`

#### Scenario: a word longer than the row

- **GIVEN** `ab abcdefghijkl` wrapped at six columns
- **THEN** the rows are `ab `, `abcdef` and `ghijkl`

#### Scenario: an indented line

- **GIVEN** `    a long indented sentence` wrapped at twelve columns
- **THEN** the first row is `    a long ` and no row is only spaces

#### Scenario: the caret at a cut

- **GIVEN** `the quick brown fox` wrapped at ten columns and the caret before
  the `b` of `brown`
- **THEN** the caret is on the second row
