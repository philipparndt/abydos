# Terminal

## ADDED Requirements

### Requirement: What a program paints is drawn as the program paired it

Bold SHALL brighten a foreground among the first eight colours to its bright
twin only when the cell's background is the terminal's own ground, and SHALL
leave the foreground as it is on a background a program painted. The tmux
client the terminal starts SHALL be told the terminal shows true colour, so a
program's 24-bit colours arrive as 24-bit. Every bundled palette SHALL keep
black as text on each of the fourteen highlight colours at 3:1 or better on
its dark ground, and the contrast check SHALL measure those pairs and name the
one that fails. A driven run SHALL be able to print, for a row, each run of
cells with the colours it holds, the colours it is drawn in, and their ratio.

Reported 2026-09-10: under the Level AAA theme k9s's selected row and its
crumbs had text that could barely be read. The bytes k9s sent were true black
on true aqua, bold; tmux made them ANSI black on bright cyan; and the bold rule
made the black into the palette's dim grey, 1.54:1 on that cyan.

#### Scenario: a program's black on its aqua

- **GIVEN** a cell holding `indexed(0)`, bold, on `indexed(14)`
- **WHEN** it is drawn
- **THEN** the text is the palette's black, not its bright black, and the pair
  reads above 3:1 in every bundled palette

#### Scenario: a bold prompt on the ground

- **GIVEN** a cell holding `indexed(4)`, bold, on the default background
- **WHEN** it is drawn
- **THEN** the text is the palette's bright blue, as it always was

#### Scenario: true colour through tmux

- **GIVEN** a pane inside the tmux this terminal started
- **WHEN** a program writes `38;2;255;0;0`
- **THEN** the cell holds `rgb(#FF0000)`, and tmux's client features include
  `RGB`

#### Scenario: the check names a pair

- **GIVEN** a palette whose black on bright cyan is under 3:1
- **WHEN** the contrast check runs
- **THEN** it reports `black on brightCyan`, the ratio and the floor, and fails

#### Scenario: reading a row's pairs from a driven run

- **GIVEN** a driven run with a coloured row in a pane
- **WHEN** `--terminal-pairs <row>` runs
- **THEN** each run of cells is printed with what it holds, what it is drawn
  in, and the ratio between the two
