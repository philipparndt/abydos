# Terminal

## ADDED Requirements

### Requirement: A scheme's colours can be read on both of its grounds

Every bundled terminal scheme SHALL have, for each of its sixteen ANSI colours,
a contrast ratio against its light ground and against its dark ground that
meets a floor the design states — one floor for the eight normal colours and
the eight bright ones alike, since a prompt, a coloured `ls` and a diff draw
on both halves. A scheme that reuses its dark table in light mode SHALL be
given a light table of its own where the numbers say so, and a test SHALL name
every pair under the floor, so that the light half of a palette is measured on
every run rather than looked at by whoever happens to use it.

Reported 2026-09-09: the light theme's terminal cannot be used, the contrast is
too low. Nobody working on the app uses the light theme, which is how a
palette's light half shipped unlooked-at.

#### Scenario: A light prompt with a coloured listing

- **GIVEN** the light theme and any bundled scheme, including the one that
  follows the editor
- **WHEN** a shell prints a prompt and a coloured `ls`, and `git diff` prints a
  change
- **THEN** every colour used is at or above the stated floor against the
  ground it is drawn on, and can be read

#### Scenario: A scheme added later

- **GIVEN** a new scheme file with a `terminal` section
- **WHEN** the suite runs
- **THEN** any of its sixteen colours under the floor on either ground fails a
  test that names the colour, the ground and the ratio

### Requirement: A palette that promises more contrast is held to it

A scheme file SHALL be able to state the contrast ratio its terminal colours
promise, as `terminal.floor`; left out, the promise is 4.5:1. The measurement SHALL hold
every colour to the floor the file promises, and the dim colour one step below
it — 3:1 under a 4.5 promise, 4.5:1 under a 7 promise — so that a palette
called high-contrast is one the suite has measured as such. The app SHALL ship
one such palette, "WCAG Level AAA", at 7:1 against every editor ground it can
be drawn on, following the editor's ground as "Editor colours" does.

#### Scenario: Choosing the AAA palette

- **GIVEN** any theme, light or dark
- **WHEN** the terminal palette is set to WCAG Level AAA
- **THEN** every ANSI colour but black reads at 7:1 or better against the
  editor ground, and bright black at 4.5:1 or better

#### Scenario: A promise the file does not keep

- **GIVEN** a scheme file that says `"floor": 7` and has a colour at 6:1
- **WHEN** the suite runs
- **THEN** the test names that colour, its ground, its ratio and the 7:1 it
  promised

#### Scenario: A floor that is not a number

- **GIVEN** a scheme file whose `terminal.floor` is a word
- **WHEN** it is read
- **THEN** the file is refused, naming `terminal.floor` and what it found
