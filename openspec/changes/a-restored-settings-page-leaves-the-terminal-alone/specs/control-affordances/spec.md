# Control Affordances

## ADDED Requirements

### Requirement: Returning to a page that is open leaves the terminal as it was

The editor SHALL leave the terminal's full screen, when a page is opened into
it — the settings page, the review pane's pages — only when the page is not yet
in the group and has to be made. Bringing forward a page that is already open SHALL
change nothing about the terminal: maximised stays maximised. Opening the page
for the first time SHALL still give the editor the window when the terminal had
all of it.

Reported 2026-09-10: with the settings page open and the terminal maximised
over it, returning to the settings un-maximised the terminal, when only the
first opening should.

#### Scenario: ⌘, with the page already open

- **GIVEN** the settings page open and the terminal maximised over it
- **WHEN** ⌘, is pressed
- **THEN** the settings page comes forward and the terminal is still maximised

#### Scenario: the first opening

- **GIVEN** no settings page in the group and the terminal maximised
- **WHEN** ⌘, is pressed
- **THEN** the terminal leaves full screen and the page is visible

#### Scenario: a driven run

- **GIVEN** a driven run with the settings page open and the panel maximised
- **WHEN** its `--settings-again` step runs
- **THEN** the panel report says maximised before and after
