## MODIFIED Requirements

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

## ADDED Requirements

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
