## ADDED Requirements

### Requirement: What the strip's controls say is drawn

The tooltips on the terminal strip's trailing controls MUST be drawn by the app
in the theme's own colours rather than shown as a system tooltip, with what the
control *is* separated from what it *does*, and a keyboard shortcut shown as a
key rather than written into the sentence.

They MUST behave as a tooltip does: shown after a pause on the control, and
gone when the pointer leaves it or anything is pressed.

#### Scenario: resting on the sessions pill

- **WHEN** the pointer rests on the sessions pill
- **THEN** a drawn tip appears naming what the two counts are, what each
  colour means, and showing ⇧⌘A as a key

#### Scenario: leaving the control

- **GIVEN** a tip on screen
- **WHEN** the pointer leaves the control
- **THEN** it goes

#### Scenario: a control with one thing to say

- **WHEN** the pointer rests on the hide button
- **THEN** the tip is one line and its key, with no second paragraph
