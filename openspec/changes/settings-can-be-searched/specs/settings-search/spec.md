# Settings Search

## Purpose

Finding a setting on a page that has grown long: what a filter matches, what it
keeps, and what it leaves alone.

## ADDED Requirements

### Requirement: The settings page can be narrowed to the rows that match

The settings window SHALL have a filter field above its sections. While it
holds text, the page SHALL show only the rows whose title or help contains
every word typed, case-insensitively, each under the heading of the section it
belongs to, in the order the section list gives them. Rows SHALL NOT move,
reorder or change what they control while filtered: the field decides what is
shown, never what is set.

#### Scenario: A word in a row's help

- **GIVEN** the settings window
- **WHEN** "ghostty" is typed into the filter
- **THEN** the Terminal section is shown with the row whose help names the
  Ghostty engine, and no row whose title and help do not contain the word

#### Scenario: Two words

- **GIVEN** the settings window
- **WHEN** "tmux status" is typed
- **THEN** only rows whose title or help contain both words remain

#### Scenario: Nothing matches

- **GIVEN** the settings window
- **WHEN** a word no row contains is typed
- **THEN** the page says that nothing matched it, in place of the sections

### Requirement: An empty filter is the page as it was

Clearing the field, or opening the window, SHALL show every section and row in
the shared section list's order, so the window with an empty field is exactly
the window today.

#### Scenario: Clearing

- **GIVEN** a filtered settings page
- **WHEN** the field is emptied
- **THEN** every section and row is shown again, in the order they had before
  the filter, with the values they have

### Requirement: A driven run can ask what a filter left

The driver SHALL be able to type into the filter and print the rows left, so
that "ghostty finds the engine row" is a claim a run can make and a test can
read, rather than a screenshot somebody has to look at.

#### Scenario: Printed

- **GIVEN** a driven run with the settings window open
- **WHEN** the verb types "ghostty"
- **THEN** the run prints the sections and row titles left, and nothing else
