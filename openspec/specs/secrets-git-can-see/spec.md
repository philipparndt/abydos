# secrets-git-can-see Specification

## Purpose
TBD - created by archiving change a-plaintext-secret-git-can-see. Update Purpose after archive.
## Requirements
### Requirement: A concealing file is asked whether git can see it

The editor SHALL ask, once when a file whose values it conceals is opened in a
project that is a git repository, whether git ignores that file and whether
git already tracks it — `git check-ignore` and `git ls-files --error-unmatch`,
one path each, off the main thread. A file the editor does not conceal, a
project that is not a repository, and a file git ignores SHALL be asked
nothing further and SHALL show no notice. The answer SHALL be asked again when
the file is reloaded from disk or the project's git state is refreshed, since
adding a line to `.gitignore` and adding the file are exactly the two acts
that change it.

#### Scenario: an ignored dotenv says nothing

- **GIVEN** a `.env` matched by a line in `.gitignore`
- **WHEN** it is opened
- **THEN** its values are covered and no exposure notice is shown

#### Scenario: a file the editor does not conceal is not asked about

- **GIVEN** `README.md` in the same repository, untracked and not ignored
- **WHEN** it is opened
- **THEN** git is not asked about it and no notice is shown

#### Scenario: outside a repository nothing is asked

- **GIVEN** a `.env` in a folder that is not a git repository
- **WHEN** it is opened
- **THEN** its values are covered and no notice is shown

### Requirement: The status bar says that git can see the file, and which case it is

The editor's status bar SHALL show, beside the secrets lock, *Not in
.gitignore* for a concealing file git neither ignores nor tracks, and
*Committed to git* for one git already tracks. The tooltip SHALL say the
consequence in a sentence — that committing the file commits the values under
the covers, or that the values are already in the history and removing the
file now does not take them out of it. The notice SHALL be drawn as the bar's
other chips are, and SHALL NOT be a modal, a toast, or a change to what the
lock says. It SHALL keep its place while the pointer is on it: a label that
moves under the pointer is one nobody can press.

#### Scenario: an unignored dotenv

- **GIVEN** `.env` holding `API_KEY=sk-abc123`, neither ignored nor tracked
- **WHEN** it is opened
- **THEN** the status bar reads *Not in .gitignore* beside the secrets lock

#### Scenario: a dotenv git already tracks

- **GIVEN** `.env` committed in an earlier commit
- **WHEN** it is opened
- **THEN** the status bar reads *Committed to git*, and its tooltip says the values are in the history already

#### Scenario: the lock still says only what it said

- **GIVEN** a `.env` showing *Not in .gitignore*
- **WHEN** the lock is pressed
- **THEN** the covers lift and the notice is unchanged

#### Scenario: the notice keeps its place under the pointer

- **GIVEN** a `.env` showing *Not in .gitignore*
- **WHEN** the pointer rests on the notice and the bar redraws
- **THEN** the notice is where it was, at the same distance from the lock

#### Scenario: ignoring the file takes the notice away

- **GIVEN** `.env` showing *Not in .gitignore*
- **WHEN** `.gitignore` gains a line matching it and the project's git state is refreshed
- **THEN** the notice goes

### Requirement: The notice offers the one thing there is to do

Pressing the notice SHALL open a menu offering to add the file to the
project's `.gitignore`, and choosing that SHALL write the file's path from the
repository root into `.gitignore`, say what was written, and ask git again — so
the notice goes by itself. For a file git already tracks the menu SHALL say
that, and SHALL NOT offer the ignore line as though it were a fix: git goes on
tracking what it tracks, and the values are in the history either way. The
project tree's own *Add to .gitignore…* dialog, where a pattern can be edited,
SHALL stay as it is for the patterns this one press does not cover.

#### Scenario: the menu offers the ignore line

- **GIVEN** `.env` showing *Not in .gitignore*
- **WHEN** the notice is pressed
- **THEN** the menu offers to add the file to `.gitignore`

#### Scenario: choosing it writes the line and the notice goes

- **GIVEN** that menu open on `.env`
- **WHEN** the ignore item is chosen
- **THEN** `.gitignore` holds `.env`, and the status bar no longer shows the notice

#### Scenario: a tracked file is not offered a fix that is not one

- **GIVEN** `.env` showing *Committed to git*
- **WHEN** the notice is pressed
- **THEN** the menu says git already tracks the file and offers no ignore line

