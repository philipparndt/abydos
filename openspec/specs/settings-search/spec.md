# settings-search Specification

## Purpose
TBD - created by archiving change settings-can-be-searched. Update Purpose after archive.
## Requirements
### Requirement: The settings page can be narrowed to the rows that match

The settings page SHALL have a filter field in its sidebar, above the
sections. While it holds text, the sidebar SHALL list only the sections with a
matching row, and the form SHALL show the matching rows of every such section
— those whose title or help contains every word typed, case-insensitively —
each under the heading of the section it belongs to, in the sidebar's order,
in place of the selected page. A row shown there SHALL control what it controls
on its own page: the field decides what is shown, never what is set.

#### Scenario: A word in a row's help

- **GIVEN** the settings window
- **WHEN** "ghostty" is typed into the filter
- **THEN** the sidebar lists Terminal and the form shows, under a Terminal
  heading, the row whose help names the Ghostty engine, and no row whose title
  and help do not contain the word

#### Scenario: Two words

- **GIVEN** the settings window
- **WHEN** "tmux status" is typed
- **THEN** only rows whose title or help contain both words remain

#### Scenario: Nothing matches

- **GIVEN** the settings window
- **WHEN** a word no row contains is typed
- **THEN** the page says that nothing matched it, in place of the sections

### Requirement: An empty filter is the page as it was

Clearing the field, or opening the window, SHALL show every section in the
sidebar and the selected section's page in the form, so the window with an
empty field is exactly the window today.

#### Scenario: Clearing

- **GIVEN** a filtered settings page
- **WHEN** the field is emptied
- **THEN** every section is listed again and the page that was selected is
  shown, with the values it has

### Requirement: A driven run can ask what a filter left

The driver SHALL be able to type into the filter and print the rows left, so
that "ghostty finds the engine row" is a claim a run can make and a test can
read, rather than a screenshot somebody has to look at.

#### Scenario: Printed

- **GIVEN** a driven run with the settings window open
- **WHEN** the verb types "ghostty"
- **THEN** the run prints the sections and row titles left, and nothing else

