## ADDED Requirements

### Requirement: Git is one button in the sidebar group

The sidebar group SHALL carry one button for git, and SHALL NOT carry a separate
button for the commit view, the branches and the history.

The rail carried three, fenced off by a separator whose comment explained that it
was there so "the strip reads as three things rather than six". A group that
needs a rule drawn round it to be understood is one button, and with the fence
gone the sidebar group is the project, git, structure and scratches.

**BREAKING**: Structure moves from ⌘4 to ⌘3 and Scratches from ⌘5 to ⌘4. For one
release the old keys open the git tool and say which key now opens what they used
to.

#### Scenario: the sidebar group

- **GIVEN** a window with a project open
- **THEN** the sidebar group is four buttons — project, git, structure, scratches
- **AND** there is no separator inside it

#### Scenario: the git tool is in front

- **GIVEN** the sidebar showing the git tool
- **THEN** the git button is lit and the others in its group are not
