## ADDED Requirements

### Requirement: A song can be shown as its patterns and notes

The song pane SHALL offer *Notes* beside *Wave*, *Spectrum* and *Both*, and in
it SHALL draw each lane as the arrangement of the tracks in it: every `play` of
a pattern as one region, from where it starts to where its last repeat ends,
named by its pattern and in its track's colour, and the notes of that region
inside it. In the *Stems* view a lane SHALL draw the tracks of its layer; in the
*Mix* view the one lane SHALL draw every track, a row each. The arrangement
SHALL be the one `mat` works out, not one worked out again by the pane. The
playhead, bar grid, sections, loop, zoom and pan SHALL be the same over notes
as over waves, and switching between *Notes* and the other modes SHALL NOT
change what is heard or where the playhead is.

Asked for 2026-09-18: "add patterns and notes of cause this requires a
appropiate zoom level".

#### Scenario: the brass stabs are three regions

- **GIVEN** `neon.song`, whose `brass` track says `at 33`, `play brass x4`,
  `at 81`, `play brass x4`, `at 105`, `play brass x4`
- **WHEN** the pane shows the stems as *Notes*
- **THEN** the `brass` lane has three regions named `brass`, starting at bars
  33, 81 and 105, each sixteen bars long — the four-bar pattern four times —
  with its passes marked, and nothing else

#### Scenario: a layer of two tracks

- **GIVEN** `neon.song`, whose `pad` track renders into the `chords` layer
- **WHEN** the pane shows the stems as *Notes*
- **THEN** the `chords` lane has the regions of both `chords` and `pad`, told
  apart by colour

#### Scenario: looking at notes does not change the sound

- **GIVEN** a song playing in the *Stems* view with `drums` switched off
- **WHEN** the mode is changed to *Notes* and back to *Both*
- **THEN** it has played on throughout, from the same place, with `drums` still
  silent

### Requirement: The notes are drawn at the detail the zoom allows

Drawn as *Notes*, a lane SHALL show no more detail than there is room for, and
SHALL show more as it is zoomed in: where a sixteenth note is narrower than two
points, regions with their names and a silhouette of their notes; closer, the
notes as bars on the lane's pitch scale, drums a row per sound, their velocity
as the strength of their colour; closer again, where a row is tall enough and a
note wide enough, each note's name and a key strip at the lane's edge. The pitch
scale SHALL be the lane's range over the whole song, so panning SHALL NOT
change which row a pitch is on.

#### Scenario: from the whole song to one bar

- **GIVEN** `neon.song` in the *Mix* view as *Notes*, fitted to the whole song
- **WHEN** it is zoomed in on bar 33 until the bar fills the pane
- **THEN** it is drawn first as named regions, then as notes without names, and
  at the last as notes with names — the `brass` row's first chord reading `C4`,
  `E♭4`, `G4`, `C5`

#### Scenario: a pan keeps the rows

- **GIVEN** the `hook` lane zoomed to four bars
- **WHEN** it is panned by eight bars
- **THEN** a `G4` is drawn on the same row before and after the pan

### Requirement: A song's notes are there before its sound, and survive a failed save

The pane SHALL take a song's arrangement from `mat export`, run beside every
render, and SHALL draw it as soon as it has it, whether or not the render has
finished. An export that fails SHALL leave the last arrangement drawn. A `mat`
whose export has no regions SHALL still have its notes drawn, without regions
around them.

#### Scenario: notes while the render runs

- **GIVEN** `neon.song`, which takes about 23 seconds to render with stems
- **WHEN** it is opened and shown as *Notes*
- **THEN** its regions and notes are drawn for the whole song while the render
  is still running

#### Scenario: a save mid-line

- **GIVEN** a song shown as *Notes*
- **WHEN** it is saved with a `play` line naming a pattern that does not exist
- **THEN** the error strip names the line, and the regions and notes of the
  last good arrangement are still drawn

### Requirement: Regions answer to the caret and reveal their source

With the caret in a `pattern` block, the pane SHALL light every region of that
pattern; in a `track` block, every region of that track. Clicking a region SHALL
put the caret on the `play` line that placed it, in whichever of the song's
files that line is written, and option-clicking it SHALL put the caret on the
pattern's definition.

#### Scenario: where does the chorus melody play

- **GIVEN** `neon.song` shown as *Notes*
- **WHEN** the caret is put inside `pattern chorus_melody`
- **THEN** every region of `chorus_melody` is lit — the `hook` lane's and the
  `lead` lane's, which plays it an octave up — and no other region is

#### Scenario: from a region to its line

- **GIVEN** `neon.song` shown as *Notes*
- **WHEN** the `brass` region at bar 81 is clicked
- **THEN** the caret is on the `play brass x4` line after `at 81`
