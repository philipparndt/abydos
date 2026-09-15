# Previews

## ADDED Requirements

### Requirement: A song opens with its sound beside it

A musik-as-text `.song` SHALL open showing its text and, beside it, the sound
`mat` renders from it — the `.scad` case with sound for a shape. The pane SHALL
render with `mat render --stems` when it is first looked at and again whenever
the file changes on disk, into a directory of its own under the temporary
directory, and SHALL NOT write into the project. It SHALL show the song as one
lane — the mix — or as one lane per layer, chosen by a switch; in the stems
view each lane SHALL be named, SHALL list the tracks rendered into it, and
SHALL have a switch that silences it for playback at once without losing the
place. With the caret in a `track` block the pane SHALL light that track's
lane; in a `pattern` block, every lane whose track plays the pattern; and
clicking a lane's name SHALL put the caret on its `track` line. A new render
SHALL take over at the playhead the old one was at, playing if it was
playing. A render that fails SHALL keep the last sound playing and show the
first error over it, and clicking it SHALL reveal the line `mat` named; a pane
that never had a sound SHALL show the failure in place of the drawing. The
lanes SHALL carry the bar grid and the song's sections, and the clock SHALL
say the bar. The pane SHALL play and pause, loop, seek, zoom and scroll as the
sound tab does, and SHALL say in words when `mat` is not installed. Stems SHALL
start on the same sample. The pane SHALL export the mix, or the mix and its
stems, as WAV, FLAC or M4A beside the song, SHALL ask before replacing a file
that is there, and SHALL NOT offer a format the installed `mat` cannot write.

Asked for 2026-09-13; export 2026-09-14.

#### Scenario: a song opens rendered

- **GIVEN** `neon.song` in a project, with `mat` installed
- **WHEN** it is opened
- **THEN** the text is on the left, the pane on the right renders it and shows
  the mix's wave and spectrum, paused at the start, with the tempo and the
  number of stems in its strip

#### Scenario: the stems, and one switched off

- **GIVEN** the pane on `drunken-sailor.song`, switched to *Stems*
- **WHEN** the drums lane's switch is clicked while playing
- **THEN** five named lanes are shown, the drums are no longer heard, the
  other four play on from where they were, and the lane is drawn as off

#### Scenario: the caret lights the stem

- **GIVEN** the stems view
- **WHEN** the caret is moved into `track pad`, and then into `pattern verse`
- **THEN** the `pad` lane is lit, and then every lane whose track plays
  `verse`

#### Scenario: a lane's name goes to the source

- **GIVEN** the stems view
- **WHEN** the `drums` lane's name is clicked
- **THEN** the caret is on the `track drums` line and the lane is lit

#### Scenario: a save while playing

- **GIVEN** the song playing at bar 12
- **WHEN** a note is changed and the file saved
- **THEN** the pane renders again, and the new render plays from bar 12

#### Scenario: a save that does not parse

- **GIVEN** the song playing
- **WHEN** an instrument's name is misspelt and the file saved
- **THEN** the sound keeps playing, a strip over it says
  `unknown instrument …` with the line, and clicking the strip puts the caret
  on that line

#### Scenario: no mat

- **GIVEN** a machine without `mat` on the login shell's PATH
- **WHEN** a `.song` is opened
- **THEN** the pane says `mat is not installed` with the `cargo install` line,
  and nothing is run

#### Scenario: exporting the song with its stems as FLAC

- **GIVEN** `neon.song` open in the pane, with a `mat` that writes FLAC
- **WHEN** *Mix and Stems as FLAC* is chosen from Export
- **THEN** `neon.flac` is written beside the song and a FLAC per layer into
  `neon stems/`, and a toast offers to reveal the file

#### Scenario: an older mat

- **GIVEN** a `mat` whose `render --help` names no `--bitrate`
- **WHEN** the Export menu is opened
- **THEN** only the WAV items can be chosen

### Requirement: A playing song is debugged as a program

Playing a song SHALL open the debugger on it unless another program is being
debugged: its heard tracks SHALL be the threads, named for what each plays; a
thread's stack SHALL be the note it is on, the pattern and pass, the `play` step
and the track, each at its line; and the debugger's continue, pause, step and
stop SHALL play, pause, move to the next bar and end. While the song plays the
threads and the shown stack SHALL follow it, and a breakpoint the song stops on
SHALL be a stop of the thread that hears the line.

Asked for 2026-09-15.

#### Scenario: stopped on a pattern's line

- **GIVEN** a breakpoint on the first line of `pattern verse`, played by `track melody`
- **WHEN** the song plays to it
- **THEN** the debugger is stopped on that line with thread `melody · verse`
  selected and the stack `verse: A4:q`, `pattern verse · pass 1 of 1`,
  `play verse`, `track melody`
