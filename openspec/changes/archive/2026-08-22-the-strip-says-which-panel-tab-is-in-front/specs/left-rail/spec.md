## ADDED Requirements

### Requirement: The rail says which pane is in front

The strip down the left edge of the window SHALL light the button of whichever
pane is on screen, and SHALL light nothing for a pane that is not.

The rail is in two groups: the sidebar tools above a separator, and below it the
panes that dock under the editor — backlog, review, debug and terminal. **Both
groups SHALL use one meaning of the fill**, which is the meaning the sidebar
group already keeps: what is on screen, rather than what was last picked.

This was reported of the bottom group, where the fill meant three different
things and two of the four buttons had no meaning at all. The backlog pane was
open and in front; its button looked exactly like a button nobody had pressed,
and the terminal button below it was lit — because lighting the terminal was
driven by the panel being open rather than by a terminal being the tab in front.

**A button SHALL NOT be lit because a container is open.** The panel being on
screen is visible from the panel being on screen, and a button that says it is
answering a question none of its neighbours answer.

#### Scenario: the backlog is in front

- **GIVEN** a window whose bottom panel is showing the backlog
- **THEN** the backlog button is lit
- **AND** the terminal button is not

#### Scenario: a terminal is in front

- **GIVEN** a window whose bottom panel is showing a terminal
- **THEN** the terminal button is lit, and the backlog button is not

#### Scenario: the panel is closed

- **GIVEN** a window whose bottom panel is closed
- **THEN** no button in the bottom group is lit on account of a pane

#### Scenario: the sidebar group is unchanged

- **GIVEN** a window whose sidebar is showing the project tree
- **THEN** the project button is lit and the others in its group are not, exactly
  as before

### Requirement: A split panel lights a button for each side

Where the panel is split, the rail SHALL light a button for the pane in front of
**each** column, not only the focused one.

Two panes are on screen and the rail has room to say so. Lighting only the
focused column's would take the fill off a pane somebody is plainly looking at,
the moment they clicked the other half — which is the fault this whole change is
about, arriving from the other direction.

#### Scenario: a terminal beside the backlog

- **GIVEN** a split panel with a terminal in front on one side and the backlog on
  the other
- **THEN** both the terminal button and the backlog button are lit
- **AND** clicking from one side to the other changes neither

### Requirement: A pane with no button leaves the rail saying nothing

A pane the rail has no button for SHALL light nothing, rather than lighting
something near it.

Search, usages and the profiler open in the same panel and are reached from
elsewhere. The rail is thirty points wide and does not carry a button for every
pane; what it must not do is answer for one of them with a neighbour's button.

#### Scenario: a search in the panel

- **GIVEN** a panel showing search results
- **THEN** no button in the bottom group is lit

### Requirement: A debug session running is said in colour

The debug button SHALL be lit while the debug pane is in front **and** while a
debug session is running, and a running session SHALL be told apart from a pane
in front by the colour of the icon rather than by the fill.

Being lit while a session runs is not this rule's to take away: it is what tells
somebody that something is being debugged **while the panel is closed**, and
nothing else on screen says it. But it cannot share one fill with "this pane is
in front" and still be readable, so the running case colours the ladybird green.

**The green SHALL be the one the theme already uses**, which is the green the
commit button carries for work not pushed. A second green chosen for this button
would be right in the default theme and wrong in somebody else's.

#### Scenario: a session running with the panel closed

- **GIVEN** a debug session running and the panel closed
- **THEN** the debug button is lit and its icon is green

#### Scenario: the debug pane in front, nothing running

- **GIVEN** the panel showing the debug pane with no session running
- **THEN** the debug button is lit and its icon is not green

#### Scenario: neither

- **GIVEN** no debug session and no debug pane in front
- **THEN** the debug button is not lit
