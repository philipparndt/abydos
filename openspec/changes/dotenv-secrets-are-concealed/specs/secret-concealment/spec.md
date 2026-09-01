# Secret concealment

## ADDED Requirements

### Requirement: Dotenv values are concealed by default

In a file whose name is dotenv-shaped — `.env`, `.env.*`, `*.env` — or a
decrypted secret file — `*.dec` — the editor
SHALL draw the value of every `KEY=VALUE` line under an opaque cover from the
moment the file opens — a cover of one fixed width for every value, saying
nothing about what it hides, its length included. Keys, comments, blank lines and lines without `=` are
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

A cover SHALL be lifted only by the file-wide reveal — the lock on the left
of the editor's status bar, labelled "Secrets hidden" while shut and
"Secrets shown" while open, and View ▸ Reveal Secrets, the same act in two
places — which lasts until toggled back. A click on a cover SHALL reveal
nothing and say how to look instead: a click is exactly what a presenter
does absentmindedly on the screen everybody is watching. The lock is absent
for a file that conceals nothing, and the whole feature can be turned off in
the editor settings, where it is on by default. The caret arriving on a line — by arrow key, by find, by a
jump — SHALL NOT reveal anything. A click's reveal SHALL end when the caret
leaves that line, so a revealed value cannot be forgotten open.

#### Scenario: arrowing through the file reveals nothing

- **GIVEN** a covered file and the caret walked through every line
- **THEN** every cover is still in place

#### Scenario: a click on a cover explains instead of revealing

- **GIVEN** a click on one cover
- **THEN** every cover is still in place, and a notice says the secrets are
  locked and where the lock is

#### Scenario: the file-wide toggle is remembered until toggled back

- **GIVEN** the status bar's lock pressed, or Reveal Secrets chosen from the
  View menu
- **THEN** every value in that tab is readable, the lock stands open saying
  "Secrets shown", and it stays so until either handle is used again — or
  until the idle limit passes

#### Scenario: a revealed file left alone covers itself

- **GIVEN** a revealed file untouched — no key, click, scroll or edit — for
  five minutes
- **THEN** the covers come back on their own and the lock shuts, so an
  unlocked document forgotten in the background does not sit open through
  the next call

#### Scenario: reading resets the clock

- **GIVEN** a revealed file being read — arrowed or scrolled through
- **THEN** it stays revealed; only five untouched minutes cover it

#### Scenario: the feature can be turned off

- **GIVEN** "Conceal secrets" switched off in the editor settings
- **THEN** open and newly opened dotenv files show their values plainly, and
  the lock is absent

### Requirement: Editing a covered value stays covered

Typing into a covered value SHALL update the document while the glyphs stay
covered, the cover following the value's width, with the caret drawn over the
cover — the way a password field takes input. The screen is exactly where a
freshly pasted key must not appear.

#### Scenario: pasting a new key under the cover

- **GIVEN** the caret placed in a covered value by clicking the line's key
  and arrowing past the `=` — the click on the key moves the caret; only a
  click on the cover itself is answered with the notice
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
