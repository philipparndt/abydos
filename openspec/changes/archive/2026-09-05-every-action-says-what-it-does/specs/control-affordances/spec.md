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
control's keyboard shortcut where the menu bar gives that command one, read
from the menu item itself rather than written out again beside the control —
so a key moved, or moved by the system on this keyboard, moves in both places
at once. A control whose command has no key in the menu SHALL name none rather
than name one it does not answer to. A control with no action and no shortcut
SHALL show no tip rather than a repeat of its own label.

#### Scenario: the run button's tip

- **WHEN** the pointer rests on the run button
- **THEN** the tip says it runs the chosen configuration, and names it

#### Scenario: the debug button's tip

- **WHEN** the pointer rests on the debug button
- **THEN** the tip says it debugs the chosen configuration and names ⌃D, the key the Run menu's Debug item answers to

#### Scenario: a command the menu gives no key is not given one here

- **GIVEN** the Run menu, where ⌃R belongs to *Run…* — the chooser — and the plain *Run* item answers to no press
- **WHEN** the pointer rests on the run button
- **THEN** its tip carries no shortcut, and the chooser beside it carries ⌃R

#### Scenario: a rail button's tip

- **WHEN** the pointer rests on the git tool's rail button
- **THEN** the app's own tip names the pane it opens, in the theme's type, and no yellow system box is shown

#### Scenario: a pane header button's tip

- **WHEN** the pointer rests on the locate button in the project pane's header
- **THEN** the tip says it selects the file the editor is showing

#### Scenario: the words are readable by a driven run

- **WHEN** a driven run hovers a named chrome control
- **THEN** it reports whether the control is lit and what its tip says, without a screenshot

### Requirement: A pane's own buttons answer the pointer too

The buttons inside a pane SHALL show the app's drawn tooltip and draw a hover
of their own, as the window's chrome does — the git panes' commit, push and
draft, the review page's check-out and submit, the pull-request list's
refresh, the scratches pane's two and the debug console's clear. A button that
is disabled SHALL neither light nor show a tip, since there is nothing there
to press. No pane button SHALL be left as a system bezel explained by
`NSView.toolTip` where it stands beside controls that are not.

#### Scenario: a scratches pane button

- **WHEN** the pointer rests on *New Scratch*
- **THEN** it lights, and the tip says what a scratch filed under this project is

#### Scenario: a pull-request list button

- **WHEN** the pointer rests on the list's refresh button
- **THEN** it lights, and the tip says the list is asked for rather than polled

#### Scenario: a button with nothing to do

- **GIVEN** a working copy with nothing staged
- **WHEN** the pointer rests on *Commit*
- **THEN** it neither lights nor shows a tip
