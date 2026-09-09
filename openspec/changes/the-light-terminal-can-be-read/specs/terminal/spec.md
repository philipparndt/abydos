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
