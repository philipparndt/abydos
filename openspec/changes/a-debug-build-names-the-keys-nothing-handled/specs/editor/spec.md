## ADDED Requirements

### Requirement: A debug build names the motion selectors nothing handled

In a debug build, the editor SHALL name an unhandled `move…` or `select…`
selector the first time one arrives, once per selector, and SHALL say nothing in
a release build.

A key that moves the caret without Shift and does nothing with it has been the
same bug three times, and each diagnosis was somebody reading the switch and
noticing which name was absent. Nothing SHALL be said for any other unhandled
selector: `noop:` and its long tail are what the quiet `default:` is for, and
they have no ceiling worth quoting. The `move`/`select` families do — 43
declared against the macOS 27.0 SDK, 29 handled, so 14 lines for the life of a
build.

#### Scenario: a key nothing handles

- **GIVEN** a debug build
- **WHEN** a key arrives as an unhandled `move…` or `select…` selector
- **THEN** that selector is named once

#### Scenario: the same key again

- **WHEN** it is pressed again, or held so that it repeats
- **THEN** nothing further is said about it

#### Scenario: everything else that arrives unhandled

- **WHEN** `noop:` or any selector outside those two families arrives
- **THEN** nothing is said

#### Scenario: a release build

- **GIVEN** a release build
- **WHEN** any unhandled selector arrives
- **THEN** nothing is said
