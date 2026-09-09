# OpenSpec Board

## ADDED Requirements

### Requirement: Every card copies its name

A change's card SHALL offer, to copy, the change's name alone — in every
column, Archived included — as the last entry of its menu, and the toast SHALL
say that the name was copied.

#### Scenario: A name from the archive

- **GIVEN** a card in Archived
- **WHEN** its menu is opened and *Copy name* chosen
- **THEN** the pasteboard holds exactly the change's name

### Requirement: A card in Writing offers the way to Ready

A change's card in Writing SHALL offer, to copy, a sentence for an assistant
that names the change and the artifacts still missing, in the schema's order —
*write the design and the spec delta for <name>, so it is ready to apply* —
with the entry's title the sentence without the name. It SHALL NOT offer
`/opsx:apply`, and it SHALL NOT run anything: the card follows the files when
the documents are written.

#### Scenario: Missing design and specs

- **GIVEN** a card in Writing with a proposal and nothing else
- **WHEN** its menu is opened
- **THEN** it offers *write the design, the spec delta and the tasks*, and
  copying puts the sentence with the change's name on the pasteboard

#### Scenario: Missing tasks only

- **GIVEN** a card in Writing with everything but `tasks.md`
- **WHEN** its menu is opened
- **THEN** it offers *write the tasks*
