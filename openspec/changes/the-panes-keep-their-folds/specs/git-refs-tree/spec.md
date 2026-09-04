# Git refs tree — delta

## ADDED Requirements

### Requirement: A recorded fold outranks the tree's arrival defaults

The tree's arrival defaults SHALL apply to a section nothing has been recorded
for, and a section a person has folded or unfolded SHALL come back the way they
left it.

The defaults are unchanged and stay for good reasons of their own: the working
copy arrives shut, because forty changed files unrolled under the first row push
the branches off the bottom of a column; each remote and `Tags` arrive shut,
because they are somebody else's account of things and are the bulk of the pane
unrolled. What none of that argues for is re-making the decision every morning
in a project where it has already been made.

The two records SHALL stay distinct. The set of sections that were *shut* is
read against the sections that arrive open; the set that were *opened* is read
against the sections that arrive shut. A single record of what is expanded
cannot be read against both.

#### Scenario: the working copy, opened once

- **GIVEN** a repository whose working copy has been unfolded
- **WHEN** the project is opened again
- **THEN** the working copy is unfolded, and its count still reads on the row

#### Scenario: a section shut against the default

- **GIVEN** the LOCAL section folded shut
- **WHEN** the project is opened again
- **THEN** LOCAL is shut, and `origin` and `Tags` are shut as they always are

#### Scenario: a repository opened for the first time

- **GIVEN** a repository with nothing recorded about it
- **THEN** the tree arrives exactly as it does today
