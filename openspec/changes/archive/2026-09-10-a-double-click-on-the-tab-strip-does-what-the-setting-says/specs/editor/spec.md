# Editor

## ADDED Requirements

### Requirement: A double-click on the tab strip's empty part does what the setting says

The editor SHALL keep a setting for what a double-click on the empty part of
its tab strip does, with three values: expand or collapse the editor, which
SHALL be the default; open a new scratch file in the project; open a new
global scratch file. The strip SHALL do exactly the one thing the setting
names, and a double-click on a tab SHALL be unaffected by it. The setting SHALL
appear in the settings page's editor section, worded as the three things and
not as their identifiers.

Asked for 2026-09-10: the gesture was hard-wired to a project scratch, and the
maintainer reaches for it to expand the editor.

#### Scenario: the default

- **GIVEN** the setting untouched
- **WHEN** the empty part of the strip is double-clicked
- **THEN** the editor is maximised, exactly as the strip's maximise button
  does; and again, and it is back

#### Scenario: a scratch in the project

- **GIVEN** the setting at *New scratch file in this project*
- **WHEN** the empty part of the strip is double-clicked
- **THEN** a scratch file opens in the project's scratch directory, as the
  strip did before this change

#### Scenario: a global scratch

- **GIVEN** the setting at *New global scratch file*
- **WHEN** the empty part of the strip is double-clicked
- **THEN** a scratch file opens in the global scratch directory

#### Scenario: a tab is still a tab

- **GIVEN** any value of the setting
- **WHEN** a preview tab is double-clicked
- **THEN** it becomes permanent, and nothing else happens
