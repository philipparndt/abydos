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

### Requirement: A lane of several tracks opens into them

Drawn as *Notes* in the *Stems* view, a lane of more than one track SHALL be a
group: closed, it SHALL draw every track of the layer in one strip on shared
rows; open, it SHALL draw each track in a strip of its own, on rows of its own,
named by its track. A chevron after the lane's name SHALL say which it is, and
a press on it or on the tracks listed beside it SHALL open or close the lane. An
open lane SHALL be as tall as that many closed ones, the other lanes giving way.
A lane that was opened SHALL stay open when a new render lands. Opening a lane
SHALL NOT change what is heard, and SHALL NOT change how the lane is drawn as
*Wave*, *Spectrum* or *Both*: a stem is one sound however many tracks made it.

Asked for 2026-09-20, of a `drums` layer of `tops`, `perc` and `rumble` whose
regions were drawn one over another and whose names read `deapble2`: "have the
track as a group that can be expanded and collapsed. In the collapsed mode it
is shown like now, in the expanded mode we have individual sub tracks."

#### Scenario: a layer of two tracks, opened

- **GIVEN** `dream.song`, whose `piano_left` track renders into the `piano` layer
- **WHEN** the pane shows the stems as *Notes* and the `piano` lane is opened
- **THEN** `theme` and `left` are regions of two strips, one named `piano` and
  one `piano_left`, neither over the other, and the lane is twice the height of
  `strings`

#### Scenario: a lane of one track

- **GIVEN** `dream.song`
- **WHEN** the pane shows the stems as *Notes*
- **THEN** `strings` has no chevron, and a press on its name reveals its block
  as before

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

### Requirement: A region has a menu, and its block can be muted from it

Drawn as *Notes*, a right-click on a region SHALL offer a menu of that block:
*Mute Block*, or *Unmute Block* when it is muted; *Go to Play Line*; and, for a
pattern's region, *Go to Pattern* with the pattern's name. Muting SHALL change
the source and nothing else: the word `mute` added at the end of what the
block's `play` line says, before any comment, in the file the line is in, as one
undoable edit of the editor, and unmuting SHALL take that word away and leave
the line as it was written. The file SHALL then be saved, so that the render
that follows is the one that is heard. A muted block SHALL keep its place and
its length — what follows it SHALL NOT move — and SHALL be drawn where it is,
without its notes, in no colour, with a broken edge and its name struck through.
The pane SHALL NOT work out for itself what a muted block does to the song:
`mat` reads the word, and says which regions are muted.

Asked for 2026-09-20: "It should also be possible to enable and disable
individual blocks. This updates the source code, maybe we need a special syntax
for muted parts so that it is easy to toggle this without messing up the code",
and "Context menu would be nice as we can also add other actions there like
jumping to the source."

#### Scenario: the kicks are muted from their region

- **GIVEN** `acid.song`, whose `drums` track says `play kicks x4` and then
  `play beat x28`
- **WHEN** *Mute Block* is chosen from the menu of the `kicks` region
- **THEN** the line reads `play kicks x4 mute` and the file is saved, the song
  renders again, `kicks` is drawn muted from bar 1 to bar 5, and `beat` still
  starts at bar 5

#### Scenario: a line with a comment

- **GIVEN** a line `  play beat x28   # the groove`
- **WHEN** its block is muted and then unmuted
- **THEN** it read `  play beat x28 mute   # the groove` in between, and reads
  as it did at first afterwards

#### Scenario: a line that makes several regions

- **GIVEN** a `play` line inside a `repeat` block, which is a region at each pass
- **WHEN** one of those regions is muted
- **THEN** every one of them is, since they are one line of the source

