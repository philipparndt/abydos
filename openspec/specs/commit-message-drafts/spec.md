# Commit message drafts

## Purpose

Drafting a commit message with Claude from the staged diff, in this repository's own voice.

## Requirements

### Requirement: A commit message can be drafted from what is staged

The commit page SHALL offer to draft a summary and a description from the staged
diff, and SHALL fill both fields with what comes back.

The staged diff and not the working copy: the draft describes the commit being
made, not everything on disk. A page with room for a description is exactly where
a blank field is hardest to start.

#### Scenario: drafting from a staged change

- **GIVEN** two staged files and an empty message
- **WHEN** a draft is asked for
- **THEN** the summary and description fields hold a draft of what those two
  files changed

#### Scenario: nothing staged

- **GIVEN** no staged changes
- **THEN** drafting is not offered

### Requirement: The draft is seeded with this project's own subjects

The request SHALL carry the recent commit subjects of this repository along with
the diff.

This repository does not write `fix: update handler`; it writes "A Java edit
reaches the JVM that is already running." A draft in a house style nobody uses
has to be rewritten, and reading the last subjects costs one `git log`.

#### Scenario: a repository with a distinctive style

- **GIVEN** a repository whose recent subjects are sentences
- **WHEN** a draft is asked for
- **THEN** the recent subjects were part of what was asked

### Requirement: A draft is never a commit

Drafting SHALL fill fields only. It SHALL NOT stage, commit, or disable the
commit button while it is running.

It fills two fields somebody was going to type into anyway, and both stay
editable. A slow answer must not become a blocked one.

#### Scenario: committing while a draft is in flight

- **GIVEN** a draft that has been asked for and has not come back
- **WHEN** a message is typed and commit pressed
- **THEN** the commit is made from what was typed

### Requirement: The draft is offered only when it can be made, and its cost is said

Drafting SHALL be visible and disabled when the `claude` command is not on the
`PATH`, with the reason on the control; it SHALL be absent only when there is
nothing it could ever describe. The first use in a project SHALL say that the
staged diff is sent to Anthropic.

The old rule made the control *absent* when the command was missing, on the
argument that a control that fails when pressed is worse than one that is not
there. That argument stands and is not what absence bought: a disabled control
cannot be pressed and so fails nothing, while an absent one cannot be
discovered — the feature was requested, on 2026-08-31, by somebody on whose
machine it already existed and was hidden. The push button is the pane's own
precedent: disabled, it says why. Sending somebody's diff off the machine is
still said plainly, once, before it happens rather than after.

#### Scenario: the command is not installed

- **GIVEN** a machine with no `claude` on the `PATH`
- **THEN** the commit page shows the drafting control disabled, and its
  tooltip says the `claude` command was not found

#### Scenario: installing the command enables it

- **GIVEN** the disabled control
- **WHEN** `claude` becomes findable and the pane refreshes
- **THEN** the control is enabled, without a restart

#### Scenario: the first draft in a project

- **GIVEN** a project in which drafting has not been used
- **WHEN** a draft is asked for
- **THEN** it is said that the staged diff will be sent, and it is asked for once

### Requirement: A diff too large to send says what it left out

When the staged diff is larger than what will be sent, the draft SHALL name the
files it did not read.

Quietly summarising half a commit produces a message that is wrong about the
other half, and nothing on screen would say so.

#### Scenario: a very large staged change

- **GIVEN** a staged diff over the size that is sent
- **WHEN** a draft is asked for
- **THEN** the draft says which files were not read

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
