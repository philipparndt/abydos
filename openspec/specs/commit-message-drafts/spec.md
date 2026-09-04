# Commit message drafts

## Purpose

Drafting a commit message with Claude from the staged diff, in this repository's own voice.
## Requirements
### Requirement: A commit message can be drafted from what is staged

The commit page SHALL offer to draft a summary and a description from the
staged diff. When both fields are empty it SHALL fill both with what comes
back; when either field holds text it SHALL NOT change either field and SHALL
offer the whole draft instead, as the requirement on a held draft says.

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
- **WHEN** a draft is asked for
- **THEN** nothing is sent, and the page says there is nothing to describe yet

#### Scenario: a draft arrives onto a typed subject

- **GIVEN** a subject typed while the draft was out, and an empty description
- **WHEN** the draft comes back
- **THEN** neither field changes, and the draft is offered on the button

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

### Requirement: A draft finds its project

A draft SHALL be delivered to the project it was asked for and to no other,
whether or not that project is still in the window when it arrives. A draft
arriving while the window shows another project SHALL be held, SHALL NOT be
written into any field or session of that other project, and SHALL be applied
when the project it belongs to is next shown on the sidebar's changes tool or
the commit page — filled when the fields are empty, offered when they are
not. Held drafts are kept in memory for the life of the app and not on disk.

#### Scenario: switching away while a draft is out

- **GIVEN** a draft asked for in project A, and the window switched to project B before it comes back
- **WHEN** the draft arrives
- **THEN** B's message is unchanged, B's session holds no part of it, and switching back to A shows the draft in A's fields

#### Scenario: the page closed by the switch

- **GIVEN** a draft asked for on A's commit page tab, which the switch to B closed
- **WHEN** the window returns to A and the commit page is opened
- **THEN** the page opens with the draft in its fields

#### Scenario: a draft for a project the window never returns to

- **GIVEN** a draft held for project A
- **WHEN** the app is quit
- **THEN** the draft is gone, and A's session on disk is as it was

### Requirement: A held draft is offered on the button, whole

A draft that arrives when either field holds text SHALL be held and offered:
the draft button SHALL read *Use draft instead* and be drawn in the palette's
red. Pressing it SHALL replace both fields with the draft, whole, as choosing
a history entry does, and SHALL never commit. Typing SHALL leave the offer
standing. Committing SHALL clear the offer. The offer SHALL survive a project
switch with the draft it carries.

#### Scenario: taking the offer

- **GIVEN** a draft offered over a typed subject
- **WHEN** *Use draft instead* is pressed
- **THEN** the subject and description are the draft's, nothing is committed, and the button reads *Draft*

#### Scenario: typing past the offer

- **GIVEN** a draft on offer
- **WHEN** more of the subject is typed and the description opened
- **THEN** the button still reads *Use draft instead* and the draft is still whole behind it

#### Scenario: committing clears the offer

- **GIVEN** a draft on offer
- **WHEN** the typed message is committed
- **THEN** the button reads *Draft* and pressing it asks for a new draft

### Requirement: The draft button says which of its three states it is in

The draft button SHALL have three states and show them: *Draft*, enabled when
a draft can be made; *Drafting* with the spinner other working buttons on the
page use, while an answer is out, with Commit still enabled; and *Use draft
instead* in red while a draft is held. Which state it is in SHALL be decided
by the page's own record of the state and not by reading the button's label.

#### Scenario: while the answer is out

- **GIVEN** a draft just asked for
- **WHEN** the page is looked at
- **THEN** the button reads *Drafting* beside a spinner, and Commit is enabled

#### Scenario: availability refreshed while offering

- **GIVEN** a draft on offer
- **WHEN** the page refreshes because `claude` left or joined the `PATH`
- **THEN** the offer is unchanged, and the button's state is still *Use draft instead*

