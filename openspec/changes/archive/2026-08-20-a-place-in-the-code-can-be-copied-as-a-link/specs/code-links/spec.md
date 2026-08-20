## ADDED Requirements

### Requirement: A place in the code can be copied as a reference

The editor SHALL copy the place the caret is in as `path:line`, relative to the
project root.

**Repo-relative, and readable.** This is the form every other tool in this
project already speaks — `ReviewSession` writes it, `Scripts/abydos` opens it, a
stack trace and a grep both look like it — and its whole value is that it can be
pasted anywhere without explanation. Nothing is added to it: no column, no
scheme, no host, no quoted line of code.

A selection SHALL be copied as a range, `path:12-18`. A person who selected
eight lines and is handed the first one has been given the wrong answer.

It SHALL be available wherever somebody is looking at code, and SHALL NOT depend
on git, a remote, or the network.

#### Scenario: the caret on a line

- **GIVEN** the caret on line 2324 of `Sources/AbydosApp/Editor/CodeView.swift`
- **WHEN** the line is copied as a reference
- **THEN** the pasteboard says `Sources/AbydosApp/Editor/CodeView.swift:2324`

#### Scenario: a selection of several lines

- **GIVEN** a selection covering lines 12 to 18
- **WHEN** it is copied as a reference
- **THEN** the pasteboard says the range, and not the first line alone

#### Scenario: a file outside any repository

- **GIVEN** a project that is not a git checkout
- **WHEN** a line is copied as a reference
- **THEN** it is copied, because a reference promises nothing about git

### Requirement: A place in the code can be copied as a permalink

The editor SHALL copy the place the caret is in as a forge URL naming a commit,
a path and a line.

A link into a branch is wrong the next time somebody edits above the line; a
link into a commit is right for ever, which is what makes it worth sending to a
person and worth keeping as a bookmark. The commit SHALL be the head of the
checkout, because that is the worktree somebody is looking at.

It SHALL be built from the repository's own remote, without the network: what a
forge calls a file at a commit is arithmetic on a URL, not a question to ask a
server.

Where there is no remote, or the remote is a host this app does not recognise,
**no URL SHALL be invented** — and the entry SHALL say which of those it was
rather than disappearing.

This is the one place the writing of this changed its own mind. "Do not offer the
entry" was the intention, and building the menu is the moment it would have to be
decided: whether a file is in a checkout, whether that checkout has a remote and
whether the host is one this app knows are three questions for git, asked
asynchronously, and a right-click cannot wait on them. An entry that appears and
vanishes under the cursor depending on questions nobody can see is worse than one
that is always there and explains itself the once.

#### Scenario: a committed line on a pushed commit

- **GIVEN** a clean checkout whose head is on the remote
- **WHEN** line 2324 of a tracked file is copied as a permalink
- **THEN** the pasteboard holds the forge's URL for that file at that commit,
  with line 2324 named in it

#### Scenario: no remote to link to

- **GIVEN** a repository with no remote configured
- **WHEN** a permalink is asked for
- **THEN** nothing is copied, and it is said that this checkout has no remote
  this app recognises

#### Scenario: a file in no repository at all

- **GIVEN** a project that is not a git checkout
- **WHEN** a permalink is asked for
- **THEN** nothing is copied, and it is said that a permalink names a commit and
  this file is not in a checkout

### Requirement: A permalink says what it cannot promise

A permalink that the person receiving it cannot open SHALL say so at the moment
it is copied.

**The two ways it can be a dead letter are both knowable here**, and both are
invisible to the person who receives it:

- **The commit is not on the remote.** Answered from the refs in this checkout —
  no fetch, no network, and never a push, which is somebody's own decision and
  not this app's. The link SHALL still be copied, because somebody may be about
  to push; what SHALL NOT happen is handing over a URL that 404s without a word.
- **The file has uncommitted changes.** The URL is not wrong — it names a real
  line of a real commit — it is simply not the line on screen. The sentence
  SHALL say that, rather than saying "uncommitted changes" and leaving the
  reader to work out what it means for their link.

#### Scenario: a commit that has not been pushed

- **GIVEN** a head commit that is on no remote-tracking branch
- **WHEN** a permalink is copied
- **THEN** it is copied, and it is said that the commit is not on the remote yet,
  so the link will not open for anybody else until it is

#### Scenario: a file edited since the last commit

- **GIVEN** a file with uncommitted changes above the caret
- **WHEN** a permalink is copied
- **THEN** it is copied, and it is said that the line on the forge is the line as
  of the commit, which is not the line on screen

### Requirement: A link followed back lands on the line the text is on now

A permalink of this app's own, whose commit is in this checkout, SHALL be opened
at the line that text is on now rather than at the number it carried.

A line number ages: text is inserted above it, a function moves, a file is
reformatted. A bookmark kept for a month and followed to line 2324 lands
wherever line 2324 happens to be, which is the failure that makes people stop
keeping bookmarks.

The line SHALL be re-found by what was on it — its text and its enclosing
symbol — which is what `BreakpointAnchors` already does for a breakpoint in a
file that changed while the app was not looking. There SHALL NOT be a second
implementation of it.

**It SHALL say when it moved somebody**, and say nothing when it did not. A
destination that quietly differs from the one in the link is worse than a wrong
one, because nobody knows to check.

A `path:line` from anywhere else SHALL be opened at the number, with nothing
inferred: this app has no idea what that file looked like when the reference was
made, and guessing would be inventing.

**There SHALL be a gesture that follows what is on the pasteboard**, since
nothing makes one of these links clickable into this app: no `abydos://` scheme
is registered and registering one is a separate piece of work. The pasteboard is
the door — one gesture, taking either form, trying the permalink first because it
is the specific shape and `path:line` would otherwise match the tail of any URL
with a colon and a number in it.

#### Scenario: a bookmark followed after the file has changed

- **GIVEN** a permalink to line 2324 at a commit, and eight lines added above it
  since
- **WHEN** the link is opened in this app
- **THEN** the editor lands on the line that text is on now
- **AND** it says that the line moved

#### Scenario: a link to a line that has not moved

- **GIVEN** a permalink to a line that is still where it was
- **WHEN** it is opened
- **THEN** the editor lands on it and says nothing

#### Scenario: a line whose text has gone

- **GIVEN** a permalink to a line that has since been deleted
- **WHEN** it is opened
- **THEN** the editor lands at the number the link carried, and says that what
  the link pointed at is no longer there

#### Scenario: somebody else's reference

- **GIVEN** `path:12` pasted from a stack trace
- **WHEN** it is opened
- **THEN** it opens at line 12, with nothing re-found and nothing said

#### Scenario: a commit this checkout has never had

- **GIVEN** a permalink naming a commit that is not in this repository
- **WHEN** it is opened
- **THEN** it opens at the number the link carried, because there is nothing to
  compare it against, and nothing is said about a line having moved

#### Scenario: something on the pasteboard that is neither

- **GIVEN** a pasteboard holding ordinary text
- **WHEN** the gesture that follows a link is used
- **THEN** nothing is opened, and it says that what is copied is neither a
  reference nor a permalink
