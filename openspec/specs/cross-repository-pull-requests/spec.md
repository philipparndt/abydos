# cross-repository-pull-requests Specification

## Purpose
TBD - created by archiving change three-hundred-submodules-are-one-working-copy. Update Purpose after archive.
## Requirements
### Requirement: A set of pull requests is raised from one description

Raising pull requests across the estate SHALL take one branch name, one title and
one body, and SHALL open a pull request in each repository that has commits on
that branch, including the superproject.

A refactoring across forty services is forty pull requests that say the same
thing, and typing that description forty times is what this replaces.

A repository with nothing on the branch SHALL be skipped and said to be skipped,
not opened empty. A repository whose pull request already exists SHALL be
reported as already open rather than attempted again.

Every request SHALL go through the `gh` this program already uses, and SHALL NOT
use a credential this program holds — the contract `pull-requests` states.

The fan-out SHALL be bounded. It is network-bound rather than disk-bound, so its
cap is sized separately from the cap on git processes, and a throttled or refused
reply SHALL be reported as itself. An empty set is a sentence about the estate; a
rate limit is a sentence about the machine, and the two must not look alike.

#### Scenario: raising a set across six changed services

- **GIVEN** six submodules with commits on `refactor/logging` and one superproject
- **WHEN** a set is raised with one title and body
- **THEN** seven pull requests are opened, each with that title and body
- **AND** every submodule with nothing on the branch is listed as skipped

#### Scenario: one repository already has the pull request

- **GIVEN** the same six, one of which already has an open pull request from that
  branch
- **WHEN** the set is raised
- **THEN** that one is reported as already open and is not opened again

#### Scenario: the forge refuses

- **GIVEN** a set large enough to be rate-limited part way through
- **WHEN** it is raised
- **THEN** the refusal is reported as a rate limit, naming which repositories
  were reached and which were not

### Requirement: A set is keyed by its branch and its state is never stored

A pull request set SHALL be identified by its branch name, and the state of each
pull request in it SHALL be read from the forge rather than recorded here.

State is: open, draft, who is assigned, who has reviewed and what they said,
whether the checks are green, and whether it is merged.

**No local record of pull request numbers SHALL be kept.** It goes stale the
moment somebody merges from the web, it knows nothing on a second machine, and it
becomes a file to reconcile after every refactoring. The forge is the record and
this program reads it.

`gh search prs` SHALL NOT be used to answer a set in one call: its indexing lags
by minutes, it is GitHub.com-shaped, and Enterprise hosts differ. Asking each
repository is slower and true.

Refreshing SHALL be asked for rather than polled, which is the choice
`pull-requests` already made for one repository and which matters more when the
set is forty.

#### Scenario: reopening a set on another machine

- **GIVEN** a set raised yesterday on a different machine
- **WHEN** the branch is opened as a set here
- **THEN** every pull request on that branch is found and its state read
- **AND** nothing had to be carried across from the machine that raised it

#### Scenario: somebody merges from the web

- **GIVEN** an open set
- **WHEN** two of its pull requests are merged in a browser and the set refreshed
- **THEN** those two read as merged

### Requirement: The set says how far along it is, and what is blocking it

A set SHALL report, as one sentence a reader can act on, how many of its pull
requests are open, how many have been reviewed, how many are merged, and how many
have failing checks.

The question a set is opened to answer is what is left, and counting forty rows
by hand is what a spreadsheet is doing today.

Rows SHALL be ordered by what needs something: failing checks first, then
awaiting review, then approved and unmerged, then merged. A row SHALL name its
repository, its number, its reviewers and its check state.

Opening a row SHALL open that pull request as the page `pull-requests` already
defines, so a review inside a set is the same review as any other.

#### Scenario: a set part way through review

- **GIVEN** a set of forty pull requests, three red, twelve unreviewed and
  twenty-five approved
- **WHEN** the set is opened
- **THEN** it says three are failing, twelve are waiting on a review and
  twenty-five are approved and unmerged
- **AND** the three red ones are the first rows

#### Scenario: a set that is finished

- **GIVEN** a set whose pull requests are all merged
- **THEN** it says so, and does not read as an empty list

