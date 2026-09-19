## 1. Regions in `mat export` (musik-as-text, on its `main`)

- [x] 1.1 `arrange.rs`: a `TimelineRegion` (kind, name, start, end, pass, repeat, transpose, file, line, pattern_file, pattern_line) pushed for every `play` step, pattern and audio, and `regions` on `TimelineTrack`
- [x] 1.2 `TimedNote.region`: the index of the region a note came from, kept through swing and humanize
- [x] 1.3 A span's file index resolved to the path as the song names it, so a `play` in an included file points at that file
- [x] 1.4 Tests in `mat-core`: `neon.song`'s `brass` track has three regions at 60, 150 and 195 s, each 30 s with a 7.5 s pass; every note of a pattern track has a region and lies within it before humanize
- [x] 1.5 `docs/` says what `regions` and `region` are; `cargo test` clean; commit on `main`, not pushed; reinstall to `~/.cargo/bin/mat`

## 2. The arrangement in AbydosKit

- [x] 2.1 `Preview/SongArrangement.swift`: the `mat export` command line, and a `Decodable` of tempo, meter, bar length, and per track name, layer, regions and notes — instruments, master and sweeps not decoded
- [x] 2.2 Pitch as note or drum name; a note's name from its MIDI number, spelled with flats as the examples write them (`E♭4`) since the export carries no spelling, and a drum's as `mat` names it
- [x] 2.3 Per lane: its tracks, their regions sorted by start, the lane's pitch range over the song padded by two semitones, drum rows in GM note order
- [x] 2.4 The level of detail as a pure function of points per sixteenth, row height and note width, with the thresholds in design decision 4
- [x] 2.5 An export without `regions` decodes to notes with no regions
- [x] 2.6 Tests: decoding a fixture cut from neon's export; brass's three regions; the `chords` lane holding `chords` and `pad`; the level chosen at the whole song, at four bars and at one bar; a pan leaving a pitch on its row

## 3. Drawing the notes

- [x] 3.1 `Editor/SongNotesDrawing.swift`: one lane's arrangement into a rect for a window and a level — regions with names and pass notches, silhouettes, notes with velocity as opacity and accents outlined, drum rows, named notes and a key strip
- [x] 3.2 Only regions intersecting the window drawn, found by binary search; silhouettes built once per arrangement
- [x] 3.3 `SongCanvas`: a *Notes* mode of its own beside `AudioCanvas.Mode`, handing each lane's rect to the drawing under the existing grid, sections, loop and playhead; the Mix lane drawing every track a row each
- [x] 3.4 The strip's choice becomes *Wave · Spectrum · Both · Notes*; changing it touches no playback
- [x] 3.5 Region colours from the theme, one per track, legible in light and dark

## 4. The pane

- [x] 4.1 `SongPreviewView+Notes.swift`: `mat export` run off the main thread beside every render, from the same fingerprint; kept only when it succeeds and matches
- [x] 4.2 Notes drawn as soon as the export lands, before the render has finished
- [x] 4.3 Caret in a `pattern` block lights its regions, in a `track` block its track's; click on a region reveals its `play` line, ⌥-click its pattern's definition, in the file each is written in
- [x] 4.4 A `mat` without `export` leaves the mode offered, empty, with a line saying why
- [x] 4.5 `SongPreviewView.swift` stays under 1,100 lines

## 5. Driving and proof

- [x] 5.1 `--song` steps: `notes` for the mode, and the report gains the level drawn, the regions on screen and the lit ones
- [ ] 5.2 A driven run over a scratchpad copy of `neon.song`: whole song → bar 33 shows the three levels; brass's regions at bars 33, 81, 105; `chorus_melody` lights `hook` and `lead`; screenshots of each level in light and dark
- [x] 5.3 Release note entry under the next version, in the 0.20.6 shape
- [ ] 5.4 `make test` and `make warnings` clean
- [x] 5.5 No `.abydos/backlog/spec` file is made untrue: the backlog is retired
