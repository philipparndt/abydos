# commit-message-drafts

## ADDED Requirements

### Requirement: A draft that writes a description shows it

Where a draft comes back with a description, the page SHALL open the description
so that what was written is on screen.

The draft is the one moment the description fills without anybody having typed in
it, and it is the moment the collapsed default would otherwise hide work that has
just been done. A draft that wrote three paragraphs behind a chevron would read
as a draft that failed.

#### Scenario: a draft with a description

- **GIVEN** the description collapsed
- **WHEN** a draft comes back with a summary and a description
- **THEN** both are filled and the description is showing

#### Scenario: a draft with only a summary

- **GIVEN** the description collapsed
- **WHEN** a draft comes back with a summary and nothing else
- **THEN** the description stays collapsed
