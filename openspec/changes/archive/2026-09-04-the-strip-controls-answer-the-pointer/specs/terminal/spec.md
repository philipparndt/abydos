## ADDED Requirements

### Requirement: The strip's trailing controls answer the pointer

A control at the trailing end of the terminal's tab strip SHALL be drawn with a
ground under it while the pointer is on it, as a tab is — the sessions pill,
the tmux session tag, the follow, maximise and hide buttons, the overflow
chevron, and the add button with its menu chevron.

Where a control draws a ground of its own, the hover SHALL be strong enough to
be seen against it rather than the same weight used behind a bare glyph.

#### Scenario: the pointer on a glyph button

- **WHEN** the pointer rests on the hide button
- **THEN** a rounded ground is drawn under it, and under nothing else

#### Scenario: the pointer on the sessions pill

- **GIVEN** the pill, which is drawn on a tint of its own
- **WHEN** the pointer rests on it
- **THEN** the ground drawn under it is visible against that tint

### Requirement: Each trailing control says what it is

Each of those controls MUST carry a tooltip saying what it is for, and where it
has a keyboard shortcut, what that is.

The sessions pill's tooltip SHALL say what each of its two counts means — that
the first counts sessions working and the second sessions waiting for somebody
— and that a finished session is counted by neither. Its two colours are the
tab badges' own, which explains them to somebody who already knows the badges
and to nobody else.

#### Scenario: reading the pill

- **WHEN** the pointer rests on the sessions pill
- **THEN** what it says names both counts, says a finished session is in
  neither, and says how to open the list

#### Scenario: reading the session tag

- **WHEN** the pointer rests on the `tmux · session` tag
- **THEN** what it says names the tmux session those tabs belong to and what
  clicking it does
