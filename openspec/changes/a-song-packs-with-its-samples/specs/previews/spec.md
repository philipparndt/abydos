## ADDED Requirements

### Requirement: A song can be packed with every file it reads

The song pane's Export menu SHALL offer to pack the song into one zip beside it,
named after it, holding the song, every file it includes and every file those
read that is the song's to hand on, with the paths in its text pointing into the
zip. Which files those are, and how the text is rewritten, SHALL be `mat pack`'s
and not worked out again by the pane. What comes with software installed where
the song is played SHALL NOT be packed, and the pane SHALL say what it is when
the pack is made. A zip already there SHALL NOT be replaced without asking. A
`mat` that cannot pack SHALL leave the item disabled, saying why.

Asked for 2026-09-21: "export everything (samples + text model to one zip
file)" and "It should get one self contianing archive".

#### Scenario: a song whose preset reads library samples

- **GIVEN** `dream.song`, whose `drums` instrument is the `house-kit` preset and
  whose piano and strings are Logic's
- **WHEN** *Song and Samples as ZIP* is chosen
- **THEN** `dream.zip` is written beside it with `dream/dream.song`,
  `dream/README.txt` and ten samples under `dream/mat-samples/`, the preset
  written out in the song with its samples pointing there, and the pane says it
  still needs the Steinway and the string ensemble from Logic

#### Scenario: unpacked elsewhere

- **GIVEN** the pack of a song that reads no installed content
- **WHEN** it is unpacked in another folder and rendered there with `mat`'s
  library out of reach
- **THEN** it renders the same sound as the song it was packed from

#### Scenario: a sample that is not there

- **GIVEN** a song naming a sample that does not exist
- **WHEN** it is packed
- **THEN** no zip is written, and the pane says which sample, in which file and
  on which line
