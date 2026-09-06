## MODIFIED Requirements

### Requirement: A tag can be made, moved onto a ref, and deleted

Tags SHALL be able to be created at a commit or a ref, moved to another, and
deleted, and the sheet that moves one SHALL resolve the target before it is
agreed to.

`GitTags.recreate` already takes anything git can resolve — a commit, a branch, a
tag — so pointing `v1` at `main` has always worked. What stopped anybody doing it
was a bare text field pre-filled with a guess and no way to see where the tag was
about to land. The field is a picker over the refs already loaded, and what the
chosen source resolves to is shown beneath it through `GitTags.describe`.

Moving a tag SHALL say what it is leaving and where that has been kept.

**Deleting one SHALL be asked for on the tag itself**, from the row's own menu
and from the keyboard, for one selected tag or several — and only where every
selected row is a tag, since a branch delete is a different question with a
different sheet. The sheet SHALL name the tags it is about to remove and where
each one points, so that what is being agreed to can be checked against what
was selected.

#### Scenario: pointing a moving tag at a branch

- **GIVEN** a tag `v1` and a branch `main`
- **WHEN** the tag's move sheet is opened and `main` chosen
- **THEN** the commit and subject `main` resolves to are shown before agreeing
- **AND** agreeing points `v1` there and says what it left, and where

#### Scenario: deleting a tag from its row

- **GIVEN** the tag `v0.9` in the tags section
- **WHEN** its delete is chosen and agreed to
- **THEN** `v0.9` is gone from the repository and from the tree

#### Scenario: the sheet says what it is about to remove

- **GIVEN** two tags selected
- **WHEN** the delete sheet opens
- **THEN** it names both tags and what each points at

#### Scenario: a selection that is not all tags

- **GIVEN** a branch row and a tag row selected together
- **THEN** the tag delete is shown disabled rather than acting on half the selection

## ADDED Requirements

### Requirement: Deleting a tag on the remote is agreed to separately

The delete sheet SHALL offer removing the tag from the remote as a choice of
its own, named after the remote — *Also delete on `origin`* — off by default,
and shown only where the repository has a remote. Locally a tag can be written
again from any commit that still exists; on the remote it is what a workflow,
a release page and everybody else's fetch reads, and the two SHALL NOT be one
agreement.

The local delete SHALL be run first, and the outcome SHALL be reported per
half: a tag gone here and still on the remote SHALL be said in those words
rather than as one failure, so nobody has to go to a terminal to find out
which state they are in. Deleting several tags SHALL NOT stop at the first
remote failure, the tags being independent of one another.

#### Scenario: local only, by default

- **GIVEN** the delete sheet open on `v0.9` in a repository with an `origin`
- **WHEN** it is agreed to without changing anything
- **THEN** the tag is deleted here and `origin` is not pushed to

#### Scenario: the remote half, asked for

- **GIVEN** the same sheet with *Also delete on `origin`* ticked
- **WHEN** it is agreed to
- **THEN** the tag is gone from this repository and from `origin`

#### Scenario: the remote refuses

- **GIVEN** a tag `origin` will not let go of
- **WHEN** the delete is agreed to with the remote ticked
- **THEN** what is said is that the tag is deleted here and still on `origin`, and why

#### Scenario: no remote to offer

- **GIVEN** a repository with no remotes
- **WHEN** the delete sheet opens
- **THEN** it offers no remote choice at all
