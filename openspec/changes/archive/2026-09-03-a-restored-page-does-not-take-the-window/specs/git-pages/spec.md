## ADDED Requirements

### Requirement: A page being restored takes nothing

A page opened because a project's session is being restored SHALL NOT change
what has the window: a maximised terminal panel stays maximised, and the page
comes back as a tab in its group.

A page somebody asks for still gives the editor the window, because while the
panel is maximised the editor is hidden and a page opened into it could not be
seen.

#### Scenario: a project that remembers a log page

- **GIVEN** a window whose terminal panel has the whole window
- **AND** a project whose session has a log page open
- **WHEN** the window switches to that project — by following its shell into it
- **THEN** the terminal still has the window
- **AND** the log page is a tab in the editor group, where it was

#### Scenario: the same page asked for

- **GIVEN** a window whose terminal panel has the whole window
- **WHEN** the log page is opened from the sidebar
- **THEN** the editor gets its share of the window back, so the page can be
  read
