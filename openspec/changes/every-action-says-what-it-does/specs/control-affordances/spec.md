## ADDED Requirements

### Requirement: A chrome control answers the pointer with a ground

Every control in the window's chrome that acts when it is clicked SHALL be
drawn with a rounded ground under it while the pointer is on it, and under
nothing else: the left rail's tool buttons, the action buttons in a sidebar
pane's header, and the titlebar's run, debug, debug-menu, scheme and status
controls. The ground SHALL be the tint and radius the terminal strip's
trailing controls already use, so that one window does not have two hovers.
Where a control draws a ground of its own — a header button that is on — the
hover SHALL remain visible against it.

#### Scenario: the pointer on a pane header's button

- **GIVEN** the project pane's header, with its collapse, locate and compact buttons
- **WHEN** the pointer rests on the collapse button
- **THEN** a rounded ground is drawn under it, and under neither of the others

#### Scenario: the pointer on the run button

- **WHEN** the pointer rests on the titlebar's run button
- **THEN** a rounded ground is drawn under it, and the debug button beside it is undrawn

#### Scenario: a control that is on

- **GIVEN** the compact-packages button, which is on and drawn on a tint of its own
- **WHEN** the pointer rests on it
- **THEN** the ground drawn under it is visible against that tint

#### Scenario: the rail keeps the hover it has

- **WHEN** the pointer rests on a left rail tool button
- **THEN** it lights as it does today

### Requirement: A chrome control says what it does, in the app's own tooltip

Every one of those controls SHALL show the app's drawn tooltip — the same
panel, delay and shape the terminal strip's controls show — rather than the
system tooltip, and no chrome control SHALL be left explained by
`NSView.toolTip`. What a tip says SHALL be what the control does, in a title,
with a detail line only where one sentence cannot carry it, and with the
control's keyboard shortcut where it has one, taken from the same place the
menu takes it. A control with no action and no shortcut SHALL show no tip
rather than a repeat of its own label.

#### Scenario: the run button's tip

- **WHEN** the pointer rests on the run button
- **THEN** the tip says it runs the chosen configuration and names ⌃R

#### Scenario: the debug button's tip

- **WHEN** the pointer rests on the debug button
- **THEN** the tip says it debugs the chosen configuration and names ⌃D

#### Scenario: a rail button's tip

- **WHEN** the pointer rests on the git tool's rail button
- **THEN** the app's own tip names the pane it opens, in the theme's type, and no yellow system box is shown

#### Scenario: a pane header button's tip

- **WHEN** the pointer rests on the locate button in the project pane's header
- **THEN** the tip says it selects the file the editor is showing

#### Scenario: the words are readable by a driven run

- **WHEN** a driven run hovers a named chrome control
- **THEN** it reports whether the control is lit and what its tip says, without a screenshot
