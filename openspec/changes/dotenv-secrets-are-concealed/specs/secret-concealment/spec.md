# Secret concealment

## ADDED Requirements

### Requirement: Dotenv values are concealed by default

In a file whose name is dotenv-shaped — `.env`, `.env.*`, `*.env` — or a
decrypted secret file — `*.dec` — the editor
SHALL draw the value of every `KEY=VALUE` line under an opaque cover from the
moment the file opens. Keys, comments, blank lines and lines without `=` are
shown as they are. A shared screen cannot wait for a signal that sharing
started: the file at risk is usually open before the call is.

#### Scenario: an api key is not on the screen

- **GIVEN** a `.env` holding `API_KEY=sk-abc123`
- **WHEN** the file is opened
- **THEN** `API_KEY=` is readable and the value is a solid cover

#### Scenario: a decrypted file is covered too

- **GIVEN** a `secrets.yaml.dec` holding `password: hunter2` — the `=` of a
  dec file may be a `:`
- **WHEN** the file is opened
- **THEN** the value after the separator is covered

#### Scenario: a comment is not a secret

- **GIVEN** a line `# rotate this monthly`
- **THEN** it is drawn uncovered

#### Scenario: an export prefix does not hide the key's name

- **GIVEN** `export TOKEN="abc"`
- **THEN** `export TOKEN=` is readable and the quoted value is covered whole

### Requirement: A value is shown only by an explicit action

A cover SHALL be lifted only by an explicit action: a click on the cover
reveals that one value, and View ▸ Reveal Secrets reveals the file until it is
toggled back. The caret arriving on a line — by arrow key, by find, by a
jump — SHALL NOT reveal anything. A click's reveal SHALL end when the caret
leaves that line, so a revealed value cannot be forgotten open.

#### Scenario: arrowing through the file reveals nothing

- **GIVEN** a covered file and the caret walked through every line
- **THEN** every cover is still in place

#### Scenario: a click reveals one value, and leaving conceals it

- **GIVEN** a click on one cover
- **THEN** that value is readable
- **WHEN** the caret moves to another line
- **THEN** the cover is back

#### Scenario: the file-wide toggle is remembered until toggled back

- **GIVEN** Reveal Secrets chosen from the View menu
- **THEN** every value in that tab is readable, and stays readable until the
  menu item is chosen again

### Requirement: Editing a covered value stays covered

Typing into a covered value SHALL update the document while the glyphs stay
covered, the cover following the value's width, with the caret drawn over the
cover — the way a password field takes input. The screen is exactly where a
freshly pasted key must not appear.

#### Scenario: pasting a new key under the cover

- **GIVEN** the caret placed in a covered value by clicking the line's key
  and arrowing past the `=`
- **WHEN** a new value is pasted
- **THEN** the document holds it and the screen never showed it

### Requirement: Concealment is a rendering and nothing else

The cover SHALL NOT change the text, offsets, undo, find, or what copying
yields: copying a covered value copies the value. Selecting and copying are
deliberate acts that put nothing on the screen, and a concealment that
corrupted copy would make the file unusable for the one person it belongs to.

#### Scenario: copy copies the secret

- **GIVEN** a covered value selected and copied
- **THEN** the pasteboard holds the real value
