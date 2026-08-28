# replace-in-file

## ADDED Requirements

### Requirement: The find bar switches to replace, and ⌘R is how

The find bar SHALL have a replace half — a field for what the matches should
become, a Replace for the current one and a Replace All — shown while the bar is
in replace mode and hidden while it is not.

⌘R SHALL open the bar in replace mode when it is closed, and switch it to replace
when it is open, leaving the keyboard in the replacement field. ⌘F SHALL open the
bar or focus the query and SHALL NOT take replace mode away: somebody who presses
⌘F to re-read what they are searching for has not asked for the replacement they
typed to be discarded.

⎋ SHALL close the whole bar, as it does for find.

#### Scenario: ⌘R with nothing open

- **GIVEN** a file open with no find bar
- **WHEN** ⌘R is pressed
- **THEN** the bar opens with both halves showing, seeded from the selection the
  way ⌘F seeds it, and the keyboard is in the replacement field

#### Scenario: ⌘R while finding

- **GIVEN** the find bar open with a query and its matches highlighted
- **WHEN** ⌘R is pressed
- **THEN** the replace half appears, the query, the switches and the matches are
  untouched, and the keyboard moves to the replacement field

#### Scenario: ⌘F while replacing

- **GIVEN** the bar in replace mode with a replacement typed
- **WHEN** ⌘F is pressed
- **THEN** the keyboard goes to the query, and the replace half and what is typed
  in it are still there

#### Scenario: the mode belongs to the tab

- **GIVEN** one tab left in replace mode and another in find
- **WHEN** the tabs are switched between
- **THEN** each shows the bar it was left with, and each keeps its own
  replacement text

### Requirement: Replacing one match replaces the current one and steps on

Replace SHALL replace the match the bar calls current — the one drawn loudest —
and then make the next match current, so that pressing it repeatedly walks the
file.

The document SHALL be edited through the same path every other edit takes, so
that one ⌘Z takes the replacement back and the tab is marked dirty as it is for
any other change.

#### Scenario: replacing the current match

- **GIVEN** three matches, the second of them current
- **WHEN** Replace is pressed
- **THEN** the second is replaced, two matches remain, and the third — now the
  second — is current

#### Scenario: taking one back

- **WHEN** ⌘Z is pressed after a replacement
- **THEN** the text that was replaced is back and the match is highlighted again

#### Scenario: nothing is current

- **GIVEN** a query with no matches
- **THEN** Replace and Replace All do nothing, and the file is not marked dirty

### Requirement: Replace All is one edit and one undo

Replace All SHALL replace every match, and SHALL be a single edit: one entry in
the undo history, whatever the number of matches.

Two hundred replacements that take two hundred ⌘Zs to take back are not a
replacement; they are a mistake somebody has to clean up by hand.

#### Scenario: replacing many

- **GIVEN** 199 matches in a file
- **WHEN** Replace All is pressed
- **THEN** all 199 are replaced, the bar reports no matches, and **one** ⌘Z puts
  the file back exactly as it was

#### Scenario: what the file becomes

- **GIVEN** matches at the first line and the last
- **WHEN** Replace All is pressed
- **THEN** the text between them that did not match is byte-for-byte what it was

### Requirement: A replacement means what the switches say it means

With the regular-expression switch off, the replacement SHALL be literal: every
character typed goes into the file as itself, `$1` included.

With it on, the replacement SHALL be a template in the same dialect the pattern is
searched with — `$0` the whole match, `$1` the first capture — because the pattern
and the template are one question asked of one engine.

#### Scenario: a literal dollar

- **GIVEN** the regular-expression switch off and a replacement of `$1`
- **WHEN** a match is replaced
- **THEN** the file holds `$1`

#### Scenario: a capture

- **GIVEN** the switch on, a pattern of `(\w+)_id` and a replacement of `$1Id`
- **WHEN** `user_id` is replaced
- **THEN** the file holds `userId`

#### Scenario: a reference to a capture that does not exist

- **GIVEN** the switch on, a pattern with two captures and a replacement naming
  `$7`
- **THEN** the bar says the replacement cannot be used, in the place it says a
  pattern is incomplete, and nothing is written to the file

### Requirement: Replace is offered only where there is something to replace

The replace half SHALL be offered for a tab whose contents can be edited, and
SHALL NOT be offered for one whose contents cannot.

A PDF is searched through PDFKit and has no text to change. A Replace button that
cannot fire says nothing; it is unlike the whole-word and regular-expression
switches, which are drawn for a PDF because they still describe the next file.

#### Scenario: a PDF tab

- **GIVEN** a PDF open and found in
- **WHEN** ⌘R is pressed
- **THEN** the bar stays as it is, with no replace half
