# Git pages — delta

## ADDED Requirements

### Requirement: A commit on a file-scoped log compares with the working copy

On a log scoped to one file, a commit's menu SHALL offer **Compare with
Working Copy**: the file as it is now against the file as that commit left
it, opened as a diff tab. Selecting the commit already shows what it changed
then; this answers the other question — how far now is from then. The verb is
absent on the whole-repository log, where "the working copy against then"
spans every file and is not a diff tab.

#### Scenario: now against an older version

- **GIVEN** a file-scoped log and a commit three versions back
- **WHEN** Compare with Working Copy is chosen on it
- **THEN** a diff tab opens showing the working copy against that version

#### Scenario: not offered on the whole log

- **GIVEN** the unscoped log
- **THEN** no commit's menu carries Compare with Working Copy
