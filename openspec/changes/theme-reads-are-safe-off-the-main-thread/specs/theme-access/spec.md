## ADDED Requirements

### Requirement: A reader of the palette sees one palette

Code reading the current theme SHALL observe a complete palette. It SHALL NOT be
possible to observe a mixture of two palettes, whatever the timing of a theme change
relative to a read.

#### Scenario: A theme changes while a view is drawing

- **WHEN** the palette is replaced while drawing code is reading colours from it
- **THEN** every colour that drawing code reads belongs to the same palette
- **AND** no colour read is nil

#### Scenario: A row draws during a theme switch

- **GIVEN** the history pane is redrawing its file rows, as it does on a resize
- **WHEN** the theme is switched at the same moment
- **THEN** the rows draw with the old palette or the new one
- **AND** the process does not abort in `NSAttributedString.size()`

### Requirement: Who may change the palette is stated and enforced

The thread on which the current theme may be assigned SHALL be defined, and an
assignment from anywhere else SHALL be prevented — by the type system where
possible, rather than by convention.

#### Scenario: An assignment from the wrong thread

- **WHEN** code attempts to change the palette from a thread that is not permitted to
- **THEN** it does not compile, or it fails loudly in a debug build
- **AND** it does not silently leave a partially assigned palette behind

#### Scenario: A reader off the permitted thread

- **WHEN** code reads the palette from a thread other than the one that may write it
- **THEN** it still observes one complete palette

### Requirement: A crash in drawing names its own site

A crash caught by the app's own handler SHALL record a symbolicated stack, so that
the frame that crashed is identified rather than approximated by the nearest
exported symbol.

#### Scenario: A caught abort is symbolicated

- **WHEN** the app's handler catches an abort in drawing code
- **THEN** `~/Library/Logs/Abydos/crash.log` names the function that crashed
- **AND** it is not necessary to guess from a nearest exported symbol, as it was for
  `showConfigurationMenu` and `stopDevPodForwards`, which were both wrong
