# Compact packages

## Purpose

A Java project spends most of its tree on directories that hold nothing but one
other directory: `src/main/java/com/example/myapp` is five rows before the first
file, four of them saying only "there is one more folder inside me", and a
reactor of fifty modules pays that fifty times over. This is the folding of such
a run into a single row — named with dots where the chain is a package and with
slashes where it is not — and the header control that turns it on, off until
somebody asks for it. The folded row *is* the last directory in the chain rather
than a stand-in for several, so every gesture the tree already has keeps working
on it without a special case. What it costs belongs here too: deciding whether a
directory folds means listing it before anybody has expanded it, which is a read
the tree was not doing at all.

## Requirements

### Requirement: A chain of single-directory folders is one row

The project view SHALL show a run of directories, each holding exactly one entry
which is itself a directory, as a single row standing for the last directory in
the run.

`src/main/java/com/example/myapp` is five rows before any code, four of which
say only "there is one more folder inside me". A reactor of fifty modules pays
that fifty times.

#### Scenario: a package chain

- **GIVEN** `com` holding only `example`, holding only `myapp`, holding source
  files
- **WHEN** compaction is on
- **THEN** the three are one row, and its children are the contents of `myapp`

#### Scenario: a directory with more than one entry ends the chain

- **GIVEN** `com` holding `example` and `other`
- **THEN** `com` is a row of its own and the chain does not fold through it

#### Scenario: a directory holding one file does not fold

- **GIVEN** `resources` holding only `logback.xml`
- **THEN** `resources` is a row of its own — the file is the row somebody clicks

#### Scenario: excluded directories are not folded away

- **GIVEN** a `target` directory holding one directory
- **THEN** `target` stays a row of its own, because what it is is the thing worth
  seeing

#### Scenario: the project root is never folded

- **GIVEN** a project whose root holds exactly one directory
- **THEN** the root keeps its own row, because its name is what says which
  project this is

### Requirement: A folded row is named for the chain it stands for

A folded row SHALL be named by joining the names in the chain: with dots where
the chain begins immediately below a directory named `java`, `kotlin` or
`scala`, and with slashes everywhere else.

Dots because that is what those directories mean — a package — and slashes
because everywhere else they are just directories, and `src.main.java` would be
a name for something nobody calls that.

#### Scenario: a package under a source root

- **GIVEN** `src/main/java/com/example/myapp`
- **WHEN** compaction is on
- **THEN** the row below `src/main/java` reads `com.example.myapp`

#### Scenario: the source root itself

- **GIVEN** `src` holding only `main`, holding only `java`
- **THEN** that row reads `src/main/java`, not `src.main.java`

#### Scenario: a chain that is not a package

- **GIVEN** `internal` holding only `platform`, holding only `store`, in a Go
  project
- **THEN** the row reads `internal/platform/store`

### Requirement: Everything that works on a directory row works on a folded one

A folded row SHALL behave as the directory it stands for: expanding, selecting,
revealing a file inside it, the context menu, renaming and dropping onto it.

The row is that directory — the last in the chain — rather than a stand-in for
several. Anything that treated it as a special kind of thing would be a second
kind of row for every gesture the tree has.

#### Scenario: revealing a file from the editor

- **GIVEN** compaction on, and a file open in the editor inside a folded chain
- **WHEN** the locate button is pressed
- **THEN** the folded row expands and the file is selected

#### Scenario: what a folded row contains

- **WHEN** a folded row is expanded
- **THEN** its children are the contents of the last directory in the chain

#### Scenario: the tool tip says the whole path

- **WHEN** the pointer rests on a folded row
- **THEN** the full path is shown, as it is for any other row

### Requirement: A control in the project view's header turns compaction on

The project view's header SHALL carry a toggle beside Collapse All and the
locate button, and the choice SHALL be remembered between sessions.

#### Scenario: turning it on

- **WHEN** the toggle is pressed
- **THEN** the tree folds its chains, and the button shows that it is on

#### Scenario: turning it off

- **WHEN** it is pressed again
- **THEN** every directory in every chain is a row of its own again

#### Scenario: it is remembered

- **GIVEN** compaction turned on
- **WHEN** the project is closed and opened again
- **THEN** it is still on

#### Scenario: off to begin with

- **GIVEN** a project opened in an app that has never been told otherwise
- **THEN** compaction is off

### Requirement: Toggling keeps the tree where it was

Turning compaction on or off SHALL keep the selection, and SHALL keep open every
row that is still a row afterwards.

A view preference that scrolls somebody back to the top is one they press once
and then work around.

#### Scenario: the selection survives

- **GIVEN** a file selected inside a chain
- **WHEN** compaction is toggled
- **THEN** the same file is selected

#### Scenario: what was open stays open

- **GIVEN** a folded row expanded, with compaction on
- **WHEN** compaction is turned off
- **THEN** the directory that row stood for is still expanded, and so is every
  directory above it

### Requirement: Deciding what folds does not make the tree slow to draw

Deciding whether a directory folds SHALL NOT list a directory more than once
per change to it, and SHALL NOT walk into excluded directories.

A directory is listed today only when somebody expands it. Knowing whether it
folds means listing it before that, once for every directory on screen — and in
a project of a quarter of a million files, walking every open directory on every
refresh is what took the main thread for most of a second before.

#### Scenario: a listing is not repeated

- **GIVEN** a directory whose modification time has not moved
- **WHEN** the tree is refreshed
- **THEN** it is not listed again

#### Scenario: excluded directories are not walked

- **GIVEN** a `node_modules` directory with thousands of entries
- **WHEN** compaction is on
- **THEN** nothing inside it is listed to decide whether it folds
