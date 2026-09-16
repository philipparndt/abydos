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

### Requirement: The debugger's Stack is a tree of every thread

The debug pane SHALL show every thread at the root of its Stack, under a group
when several threads share one, with each thread's frames under it — nested
when the adapter names each frame's parent, as a list otherwise — and SHALL
open the thread being shown and the threads its adapter says are busy. For a
song, a pattern's lines SHALL be side by side inside the pattern, a line with no
note sounding shown dimmed with its last note.

Asked for 2026-09-15.

#### Scenario: a breakpoint while four tracks play

- **GIVEN** the shanty stopped on the first line of `pattern verse`
- **WHEN** the Stack is shown
- **THEN** every playing track is open to its pattern's lines, the resting one
  is shut and dimmed, and `verse: A4:q` is selected and scrolled into sight

### Requirement: A song is played while it renders

The pane SHALL render a song once and play it as it is written: with a `mat`
that streams, the mix SHALL be played from its first stretch and each stretch
written after it SHALL be played straight on from the last, without a seam and
without moving the playhead, and the stems SHALL land at the end. A render that
is still being written SHALL take over from a song that is playing only once it
has reached the playhead. A render that falls behind what is being played SHALL
leave the playhead where it is and go on when more is written, rather than
reporting the end of the song. A `mat` that does not stream SHALL still render
the whole song, which is then heard when it lands.

Asked for 2026-09-16.

#### Scenario: a cold song is heard before it has rendered

- **GIVEN** a song of 3:35 nothing has rendered, and a `mat` that streams
- **WHEN** the pane opens it and it is played
- **THEN** it is playing while `mat` is still running, with as much of the song
  as has been written, the playhead runs on unbroken as the rest arrives, and
  one render — not two — produces the whole song and its stems

### Requirement: A few bars of a song loop while it is changed

Option-clicking a line's bar in a song's gutter SHALL loop the stretch of the
song where that line is heard and play it, option-clicking the same line again
SHALL stop looping, and a render landing while it loops SHALL keep looping the
same stretch. The pane SHALL show what the loop leaves out as dimmed and say
which bars it plays.

Asked for 2026-09-16.

#### Scenario: looping a pattern's line while its sound is changed

- **GIVEN** the shanty playing, and the first line of `pattern verse`, heard at bars 5–6
- **WHEN** its bar is option-clicked, and the kit's snare is then changed and saved
- **THEN** those two bars play round and round, the clock says `loop bars 5–6`,
  and the new sound is heard on the next pass
