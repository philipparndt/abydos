## ADDED Requirements

### Requirement: The search pane searches the project the window is showing

The search pane SHALL search whichever project the window is on, and SHALL follow
a switch without being closed and reopened. It is made once and cached for the
life of the window — under the panel, under the project view, or in a window of
its own — and it holds the root it was made with.

**This matters more than a stale board does, because this pane opens files.** A
result list from a tree the window has left is a list of paths that still open,
in a project nobody is looking at.

Results from the project that was left SHALL be cleared, since a result is a
path and those paths are not answers about the project now showing. The query
SHALL survive: it is what somebody typed, and it costs nothing to ask again.

#### Scenario: searching after a switch

- **GIVEN** a search pane with results from one project
- **WHEN** the window switches to another project and the same query is run
- **THEN** every result is in the second project

#### Scenario: the results that were on screen

- **GIVEN** those results showing
- **WHEN** the project is switched
- **THEN** they are gone rather than left to be clicked

#### Scenario: what was typed

- **GIVEN** a query in the field
- **WHEN** the project is switched
- **THEN** the query is still there
