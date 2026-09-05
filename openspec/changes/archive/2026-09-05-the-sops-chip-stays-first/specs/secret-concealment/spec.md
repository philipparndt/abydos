## MODIFIED Requirements

### Requirement: A value is shown only by an explicit action

A cover SHALL be lifted only by the file-wide reveal — the lock in the
editor's status bar, labelled "Secrets hidden" while shut and
"Secrets shown" while open, and View ▸ Reveal Secrets, the same act in two
places — which lasts until toggled back. A click on a cover SHALL reveal
nothing and say how to look instead: a click is exactly what a presenter
does absentmindedly on the screen everybody is watching. The lock is absent
for a file that conceals nothing, and the whole feature can be turned off in
the editor settings, where it is on by default. The caret arriving on a line — by arrow key, by find, by a
jump — SHALL NOT reveal anything. A click's reveal SHALL end when the caret
leaves that line, so a revealed value cannot be forgotten open.

The SOPS chip SHALL keep its place at the bar's left edge in every state, and
the lock SHALL follow it when both are shown, at the edge on its own for a
file that conceals without being SOPS's: the chip is the file's encryption
and the lock is its covers, and pressing one SHALL NOT change the other.

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
  unlocked document forgotten in the background does not sit open through the
  next call

#### Scenario: reading resets the clock

- **GIVEN** a revealed file being read — arrowed or scrolled through
- **THEN** it stays revealed; only five untouched minutes cover it

#### Scenario: the feature can be turned off

- **GIVEN** "Conceal secrets" switched off in the editor settings
- **THEN** open and newly opened dotenv files show their values plainly, and
  the lock is absent

#### Scenario: the lock beside the chip

- **GIVEN** a decrypted SOPS file with its values covered
- **WHEN** the lock is pressed
- **THEN** the values are shown, the chip still reads *SOPS · decrypted*, and
  neither chip nor lock has moved
