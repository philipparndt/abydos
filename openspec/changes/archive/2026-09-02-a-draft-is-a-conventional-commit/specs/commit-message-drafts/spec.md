# Commit message drafts — delta

## ADDED Requirements

### Requirement: A draft is a Conventional Commit by default

A drafted summary SHALL be asked for in
[Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
form — `<type>[optional scope][!]: <description>` — where the type is one of
`feat`, `fix`, `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf` or
`test`, a scope is a noun in parentheses naming a part of the codebase, and a
breaking change is marked either by `!` before the colon or by a
`BREAKING CHANGE:` footer in the description.

A setting SHALL choose this, and SHALL be on by default. With it off, the
draft is asked for in the repository's own voice, exactly as it was before this
requirement existed.

What comes back SHALL NOT be rewritten into the format. Prepending a type to a
summary that lacks one is classifying somebody's change on their behalf, and a
wrong classification reads as deliberate and lands in a changelog under the
wrong heading. Both fields stay editable, which is the recovery.

The format is what changelog, release and version tooling reads. A draft in
prose has to be rewritten by hand before it can be committed in a repository
that uses any of them, and prescribing a standard is a better default than
prescribing one house's voice.

#### Scenario: the default draft

- **GIVEN** a project in which the setting has not been changed
- **WHEN** a draft is asked for
- **THEN** what was asked for names the Conventional Commits form and every
  one of the ten types

#### Scenario: the setting turned off

- **GIVEN** the setting off
- **WHEN** a draft is asked for
- **THEN** what was asked for is what it was before the format existed, and
  says nothing about types

#### Scenario: an answer outside the format

- **GIVEN** the setting on
- **WHEN** a draft comes back with a summary carrying no type
- **THEN** the fields hold what came back, unchanged and editable

## MODIFIED Requirements

### Requirement: The draft is seeded with this project's own subjects

The request SHALL carry the recent commit subjects of this repository along with
the diff, whichever shape the draft is asked for in.

With the Conventional Commits form prescribed, the subjects SHALL be described
in the request as the source of its words and its scope names rather than of the
subject line's shape: twenty narrative subjects and an instruction to write
`feat(scope): …` are contradictory, and examples usually win. The scope is the
half of the format a diff alone does not settle — `fix(navigator):` against
`fix(ProjectNavigatorViewController):` is the difference between a scope and a
file name — and the recent subjects are where a repository's own nouns are
written down.

With the form turned off, the subjects are the house style itself: a draft in a
voice nobody uses has to be rewritten, and reading the last subjects costs one
`git log`.

#### Scenario: a repository with a distinctive style

- **GIVEN** a repository whose recent subjects are sentences
- **WHEN** a draft is asked for
- **THEN** the recent subjects were part of what was asked

#### Scenario: the subjects under a prescribed format

- **GIVEN** the Conventional Commits form on
- **WHEN** a draft is asked for
- **THEN** the subjects are still sent, and what was asked says they are there
  for the words and the scope names
