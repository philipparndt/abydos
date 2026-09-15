# Language servers

## ADDED Requirements

### Requirement: A song's language server is its renderer

A `.song` file SHALL be the `song` language, and its language server SHALL be
`mat lsp` — a subcommand of the `mat` that renders it, found the way every
tool is. The server SHALL report the parser's and the arranger's diagnostics
as the file is typed, with the hints `mat check` prints; SHALL complete the
block keywords at column one, the settings a block takes by its instrument's
kind, a setting's options, and the names the song defines where a name is
expected; SHALL answer hover on a keyword with what it means and on a name
with the named block's lines; SHALL go from a track's `instrument`, `play`
and `sidechain` lines to the block they name; and SHALL list the blocks and
sections as symbols. When `mat` is not installed the banner SHALL say so with
the install line, as for any other server, and the file SHALL still open as
text.

Asked for 2026-09-13.

#### Scenario: a misspelt instrument

- **GIVEN** a song whose track says `instrument brasss`
- **WHEN** it is opened with `mat` on the PATH
- **THEN** the line carries `unknown instrument 'brasss'` with the hint
  `did you mean 'brass'?` before anything is rendered

#### Scenario: completing a name

- **GIVEN** the caret after `instrument ` in a track block
- **WHEN** completion is asked for
- **THEN** the song's instruments are offered, and nothing else

#### Scenario: the settings of a kind

- **GIVEN** the caret on an indented line under `instrument kit drums`
- **WHEN** completion is asked for
- **THEN** `kick`, `snare` and the other voices are offered, and `osc` is not

#### Scenario: go to the instrument

- **GIVEN** the caret on `brass` in a track's `instrument brass`
- **WHEN** go-to-definition is invoked
- **THEN** the caret moves to `instrument brass synth`

#### Scenario: no mat

- **GIVEN** a machine without `mat` on the PATH
- **WHEN** a song is opened
- **THEN** the banner offers the `cargo install` line, and the text is edited
  without a server

### Requirement: A song's lines show where in the song they are heard

The song server SHALL send, after each analysis of text that parses, where each
line is heard — a `play` step across its repeats, a pattern's line wherever the
pattern plays from its first note to the end of its last, a track's or an
instrument's header wherever what it names is heard, a section across its bars
— and the editor SHALL draw beside each such line's number a bar the length of
the song, lit where the line is heard, and SHALL say the bars and times when the
pointer is over it. A line heard nowhere SHALL draw no bar, a click on a bar
SHALL NOT make a breakpoint, and text that does not parse SHALL leave the last
bars in place.

Asked for 2026-09-14.

#### Scenario: a pattern played twice

- **GIVEN** `pattern verse`, played at bars 5–12 and again at bars 21–28
- **WHEN** the song is opened
- **THEN** the pattern's header shows two lit stretches, its first line two
  short ones at bars 5–6 and 21–22, and hovering the header says
  `2 times: bars 5–12, 21–28`

#### Scenario: a setting

- **GIVEN** an `osc` line inside an instrument
- **WHEN** the song is opened
- **THEN** the line has no bar

### Requirement: The bars carry the playhead and seek the song

While the song pane has a playhead, each line's bar SHALL draw it as a tick at
the playhead's place in the song, moving as the song plays, and a click on a
bar SHALL move the playhead to the time under the pointer, and dragging SHALL
scrub it. A click on a line with no bar SHALL move nothing.

Asked for 2026-09-15.

#### Scenario: a click halfway along

- **GIVEN** a track heard across the whole song, and the song paused at 0:10
- **WHEN** its bar is clicked halfway along
- **THEN** the playhead is at half the song's length, and every bar's tick is
  drawn there

### Requirement: A song's gutter shows time codes, and hides its columns as blame hides

The editor SHALL draw, beside each line of a song heard somewhere, the time it
is first heard, as `0:07.272`, and a click on it SHALL move the song's playhead
to the next time the line is heard after the playhead, or to its first. The
gutter's menu and the Editor menu SHALL show and hide the time codes and the
timeline bars, each on its own, and the choice SHALL be remembered.

Asked for 2026-09-15.

#### Scenario: a pattern's line clicked twice

- **GIVEN** the first line of `pattern verse`, heard at 0:07.272 and again later
- **WHEN** its time code is clicked, and clicked again
- **THEN** the playhead is at 0:07.272, and then at the second time

#### Scenario: hiding the time codes

- **GIVEN** a song with both columns showing
- **WHEN** *Hide Time Codes* is chosen from the gutter's menu
- **THEN** the gutter is narrower by the time-code column, the bars stay, and a
  song opened afterwards shows no time codes

### Requirement: A playing song marks the lines heard, and stops on breakpoints

While a song plays, the editor SHALL mark every line heard at the playhead the
way the debugger marks the line it stopped on, and SHALL light the note, chord
or grid cell under the playhead on each line of a pattern. A song playing past the moment a
line with an enabled breakpoint starts to be heard SHALL pause there, with the
playhead on that moment and the line marked as stopped and scrolled to; play
SHALL go on from it without stopping on the same breakpoint again, and a seek
SHALL NOT stop on a breakpoint it jumps past.

Asked for 2026-09-15.

#### Scenario: a breakpoint in a pattern

- **GIVEN** a breakpoint on the first line of `pattern verse`, first heard at
  0:07.272, and the song playing from 0:05
- **WHEN** the playhead reaches 0:07.272
- **THEN** the song pauses at 0:07.272, that line is marked as stopped, the
  other lines heard there are marked too, and the line's first note is lit
