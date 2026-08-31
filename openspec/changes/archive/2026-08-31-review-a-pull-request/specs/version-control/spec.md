# version-control

## ADDED Requirements

### Requirement: A checkout made for a pull request says that is what it is

A worktree this program created on a pull request's behalf SHALL be
distinguishable in the list of checkouts from one somebody made by name, and
SHALL be removable from where it was made.

The list of checkouts is a list of places somebody chose to work. A checkout
made to read somebody else's branch is a different kind of thing: it is
temporary, it belongs to a review rather than to a piece of work, and it will
accumulate — a repository whose reviewer opens three pull requests a day
otherwise grows a checkout a day, each named after a stranger's branch, and the
menu that was ordered, capped and honest becomes a list nobody reads.

Saying which ones those are is what makes them collectable. Removing one SHALL
obey the rule the branches pane already keeps: a checkout holding changes
refuses rather than discarding them, whoever made it.

#### Scenario: a checkout made for a review

- **GIVEN** a pull request whose branch has been checked out to read it
- **WHEN** the list of checkouts is opened
- **THEN** that one is shown as belonging to the pull request it was made for

#### Scenario: finishing with it

- **GIVEN** such a checkout with nothing modified in it
- **WHEN** it is finished with
- **THEN** it is removed, and the list of checkouts is shorter by one

#### Scenario: finishing with one that has been worked in

- **GIVEN** such a checkout with uncommitted changes in it
- **WHEN** it is finished with
- **THEN** it refuses, and says what is in it
