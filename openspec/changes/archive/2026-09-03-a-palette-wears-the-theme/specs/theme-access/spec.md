## ADDED Requirements

### Requirement: A window the app makes takes its appearance from the theme

Every window the app puts on screen SHALL have its `appearance` set from
`Theme.current` rather than inherited from the machine, and SHALL be given it
each time it is shown rather than once when it is made — a window that is kept
between showings outlives a theme change.

This is what decides the parts of a window the app does not draw: the title
bar's material, a search field's bezel, a scroller. A light theme on a dark Mac
otherwise draws a dark strip across the top of a light list, which is how this
was found.

#### Scenario: a light theme on a dark Mac

- **GIVEN** the machine in dark mode and the app on a light theme
- **WHEN** a palette is opened
- **THEN** the band holding its filter and the filter's own bezel are light,
  like the rows below them

#### Scenario: the theme changed while a palette was put away

- **GIVEN** a palette that has been opened and closed
- **WHEN** the theme is changed and the palette opened again
- **THEN** it comes up in the new theme
