# Terminal

## ADDED Requirements

### Requirement: A palette is legible on what programs paint, not only on the ground

A bundled palette SHALL keep every painted pair — `black`, `brightBlack`,
`white`, `brightWhite` and the default foreground as text, on each of the
sixteen palette colours as a background — at 3:1 or better, on both of its
grounds, and the contrast check SHALL measure those pairs and name the one that
fails. The dim colour `brightBlack` SHALL be held to 3:1 on the ground whatever
the palette promises, since a colour held higher on the ground is that much
lower on every light background a program paints. Dim text SHALL be drawn at
45% of its foreground only while that keeps 3:1 against the cell's own
background, and SHALL be drawn undimmed otherwise, so dimming never makes a
pair worse than the program painted.

Reported 2026-09-10: under the Level AAA theme k9s's selected row and its
crumbs had text that could barely be read, both readable under the palette
before. Computed from the scheme file, the dim colour on the palette's bright
blue is 1.54:1 and the dimmed default foreground over it 1.26:1.

#### Scenario: the dim colour on a program's selection

- **GIVEN** the AAA dark palette
- **WHEN** `brightBlack` text is drawn on a `brightBlue` background
- **THEN** the pair reads at 3:1 or better

#### Scenario: dim text over a painted background

- **GIVEN** a cell with `dim` set whose background a program painted light
- **WHEN** it is drawn
- **THEN** the text is dimmed only if it still reaches 3:1 against that
  background, and drawn undimmed otherwise

#### Scenario: dim text on the ground

- **GIVEN** a cell with `dim` set on the terminal's own ground
- **WHEN** it is drawn
- **THEN** it is drawn at 45%, exactly as before

#### Scenario: the check names the pair

- **GIVEN** a palette whose `brightBlack` on `brightYellow` is under 3:1
- **WHEN** the contrast check runs
- **THEN** it reports that pair, its ratio and the floor, and fails

#### Scenario: the palette's own promise stands

- **GIVEN** the AAA palette after the fix
- **WHEN** its fourteen text colours are measured against the ground
- **THEN** each still reaches 7:1
