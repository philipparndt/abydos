# Previews

## ADDED Requirements

### Requirement: A sound file is cut to a selection

In a sound file's tab, `i` SHALL set the selection's in-point and `o` its
out-point at the playhead, in either order, and Escape SHALL clear it. The
selection SHALL be drawn across the wave and the spectrum. *Keep Selection*
(`k`) SHALL leave only the selected frames and *Delete Selection* (`⌫`)
SHALL remove them and join the frames either side; both SHALL be exact to
the frame and SHALL add no fades. A cut SHALL NOT write the file: the tab
SHALL show that it has unsaved changes, ⌘Z and ⇧⌘Z SHALL undo and redo cuts,
closing the tab SHALL ask whether to save, and ⌘S SHALL write the file in its
own format by replacing it whole. A file in a format macOS cannot encode SHALL
keep its edit and say why it was not saved.

The pane SHALL also write a selection to a file of its own, in the format the
source is in and the container the name asks for, leaving the file being played
unchanged; it SHALL offer a name carrying where in the source the selection
starts. A second `i` SHALL move the start to where the selection ended and drop
the end, and a second `o` SHALL move the end to where it began and drop the
start, so one selection carries on from the last.

Asked for 2026-09-14; writing a selection and carrying one on, 2026-09-16.

#### Scenario: a recording is cut into samples one after another

- **GIVEN** a long take with a selection between 0:12 and 0:14
- **WHEN** *Save Selection As…* writes it, `i` is pressed twice, the playhead
  runs on and `o` marks 0:19
- **THEN** the first file holds 0:12 to 0:14 and is named for 0:12, the take on
  disk is unchanged, and the selection is now 0:14 to 0:19

#### Scenario: keeping two bars of a take

- **GIVEN** an eight-second `take.wav` with the playhead at 2 s
- **WHEN** `i` is pressed, the playhead moved to 4 s, `o` pressed, and `k`
- **THEN** the tab plays a two-second file, shows the edited dot, and
  `take.wav` on disk is still eight seconds

#### Scenario: deleting a cough

- **GIVEN** the same take with 3 s to 3.5 s selected
- **WHEN** `⌫` is pressed and then ⌘S
- **THEN** `take.wav` is 7.5 s long, its frames after 3 s are the frames that
  were after 3.5 s, and the dot is gone

#### Scenario: undo

- **GIVEN** a cut not yet saved
- **WHEN** ⌘Z is pressed
- **THEN** the tab plays the file as it was, and shows no edit

#### Scenario: an MP3

- **GIVEN** `song.mp3` with a selection deleted
- **WHEN** ⌘S is pressed
- **THEN** the file is not written, the edit is kept, and the tab says macOS
  cannot write MP3
