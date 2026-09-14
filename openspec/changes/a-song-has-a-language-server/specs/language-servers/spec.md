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
