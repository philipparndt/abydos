# Commit message history

## ADDED Requirements

### Requirement: The commit page offers the repository's recent messages

The commit page SHALL offer the last twenty commit messages of the repository
from a history control beside the summary field, each entry shown by its
subject with its date beside it, read from the log when the menu opens.

A message like the last one — a repeated chore, a second try after an amend,
yesterday's subject shape — had to be retyped or fished out of the log page by
hand.

#### Scenario: the menu holds the recent subjects

- **GIVEN** a repository whose last commits are "one", "two" and "three"
- **WHEN** the history menu is opened
- **THEN** its entries are "three", "two", "one", newest first

#### Scenario: a repository with no commits

- **GIVEN** a freshly initialised repository
- **THEN** no history control is offered — there is no history to show

### Requirement: Choosing an entry fills both fields

Choosing a history entry SHALL fill the summary field with that commit's
subject and the description field with its body, replacing what the fields
held — choosing is the explicit decision to replace, unlike a refresh, which
never touches typing.

#### Scenario: a message with a body

- **GIVEN** a past commit with a subject and a two-line body
- **WHEN** its entry is chosen
- **THEN** the summary field holds the subject and the description field the
  body

#### Scenario: typed text is replaced, not merged

- **GIVEN** half a sentence typed into the summary
- **WHEN** an entry is chosen
- **THEN** the fields hold the chosen message and only it, still editable

### Requirement: Filling from history is never a commit

Choosing an entry SHALL stage nothing, commit nothing, and disable nothing —
the rule drafting already keeps, kept here too.

#### Scenario: nothing happens but the fields

- **GIVEN** staged changes and an entry chosen
- **WHEN** the fill lands
- **THEN** the staged changes are exactly what they were and no commit was
  made
