## Context

The song pane (`SongPreviewView`, `SongCanvas`) draws lanes on one timeline:
the mix as one lane, or a lane per *layer* (`mat`'s stem groups — `pad` renders
into the `chords` layer in `neon.song`, so a lane can hold several tracks). Each
lane is drawn as *Wave*, *Spectrum* or *Both* (`AudioCanvas.Mode`), under a bar
grid, sections, a playhead and a loop, with pinch and ⌥-scroll zoom down to
`shortestSpan` (20 ms) and a position bar while zoomed.

`mat export <song>` prints the arranged timeline as JSON: per track its name,
layer, instrument and every note — `start` and `duration` in seconds, `pitch`
as `{"Note": 60.0}` or `{"Drum": "kick"}`, `midi`, `velocity`, `accent`,
`slide`. Measured on `neon.song`: 14 ms, 1.5 MB, 12 tracks, 4,997 notes. Most
of the bytes are instrument zones and settings, which the pane does not need.

What it lacks is the pattern a note came from. `arrange.rs` walks each track's
steps (`at`, `rest`, `play <pattern> xN transpose=… velocity=…`, audio `play`)
with a cursor, and for a `play` pushes the pattern's events `repeat` times; the
`TrackStep::Play` it read has a `Span` with the file index and line, and the
pattern has its own span. Both are dropped once the notes exist.

## Goals / Non-Goals

**Goals:**

- The arrangement of a song — regions on lanes, notes in regions — drawn in the
  pane, readable at the zoom it is looked at.
- Taken from `mat`, which is the one thing that knows where a `play` lands, not
  worked out again in Abydos.
- Everything the pane already does over waves — playhead, grid, sections, loop,
  zoom, pan, lane switches, caret light — also over notes.

**Non-Goals:**

- Editing. Dragging a region or a note writes nothing into the song; the source
  is the one place a song is changed. A later change can map a drag onto a text
  edit, and this one does not pretend to.
- A separate piano-roll editor window, Logic's *Piano Roll* pane under the
  tracks. The detail comes from zooming the lanes, as asked.
- Vertical zoom inside a lane. Lanes keep the heights they have; see *Open
  questions*.
- Automation — `sweeps` — and sidechain drawn over the notes. The data is in the
  export; drawing it is its own change.
- Syntax colouring for `.song`; still no grammar.

## Decisions

### 1. The regions come from `mat export`, extended on `mat`'s `main`

`TimelineTrack` gains `regions: Vec<TimelineRegion>`:

```
{ "kind": "pattern" | "audio", "name": "brass",
  "start": 60.0, "end": 90.0, "pass": 7.5, "repeat": 4, "transpose": 0,
  "file": "neon.song", "line": 307, "pattern_file": "neon.song", "pattern_line": 70 }
```

and `TimedNote` gains `region: Option<usize>`, an index into its track's
regions. One region per `play`, with `repeat` kept rather than one region per
pass: Logic draws a looped region as one block with its pass boundaries marked,
and that is also what the source says — one line, `x4`. `file` is the path as
the song names it, relative to the song, so an included file's `play` points at
that file. Audio `play` steps become `kind: "audio"` regions with no notes.

Swing and humanize move notes after they are placed; the region is the
placement, so a humanized note can start a few milliseconds before its region.
The drawing clips a note to its region.

*Ruled out:*
- **Working out the regions in Abydos** from `SongSource`'s blocks. It would be
  a second implementation of `at`/`rest`/`repeat`/`include`, drifting from
  `mat`'s the first time the format grows a step — the pane would draw a chorus
  at bar 33 that plays at bar 34.
- **One region per pass.** Four blocks for one `x4` line, and a label on each
  that the source does not have.
- **Putting the arrangement into the render's `manifest.json`.** It would only
  arrive when the stems do, which for neon is 23 s after the first sound; the
  point of drawing notes is also to see a song whose render is still running or
  has failed on a sample. The export needs no audio at all.

### 2. Abydos runs `mat export` beside every render, and decodes a part of it

`SongArrangement` (AbydosKit) is the command line and a `Decodable` of tracks
→ name, layer, regions, notes, plus `bar_seconds`, `meter` and `tempo`;
instruments, master and sweeps are not declared and so not decoded. It runs
off the main thread when a render starts, reading the file on disk as the
render does. A result replaces the last only when it succeeds: an export that
fails — the same save mid-line that fails a render — leaves the last
arrangement drawn, and says nothing of its own, since the render's error strip
already says what is wrong with the file.

An older `mat` without `regions` still gives notes: the lane draws them with
no region blocks around them. A `mat` without `export` at all — it says
"unrecognized subcommand" — leaves the mode offered but empty with a line
saying why, rather than hiding it. It is told from what the export says rather
than by asking `mat --help` first, which would be a second process for the
answer the first one gives anyway.

`mat export` is asked to write to a file (`-o`), not to its standard output:
what it says about a broken song comes on the error stream, and reading one
pipe to its end while the other fills is a process that never finishes.

*Ruled out:* a `mat export --slim` flag to drop the 1.5 MB of instruments.
Decoding the part wanted out of 1.5 MB is a few milliseconds off the main
thread; a flag is a second output format to keep true. Revisit if a song's
export is measured to be slow.

### 3. *Notes* is a fourth drawing mode, not a third view

`AudioCanvas.Mode` is what each lane is drawn as, and *Mix / Stems* is which
lanes there are and what is heard. Notes are another way to draw a lane, so the
mode choice becomes *Wave · Spectrum · Both · Notes*, and the Mix/Stems switch
keeps its meaning. In the *Stems* view each layer lane draws the tracks in it.
In the *Mix* view the one lane draws every track, a thin row each, which is the
whole arrangement at a glance — Logic's tracks area, folded into the height of
one lane.

*Ruled out:* a *Notes* view beside *Mix* and *Stems*. It would couple what is
drawn to what is heard: choosing to look at notes would change which files
play. It would also give the sound file's player (`AudioCanvas`) a mode it has
no data for, so `Notes` lives in `SongCanvas`'s own mode, and `AudioCanvas.Mode`
is not extended; the song strip's choice maps onto both.

### 4. The level of detail is chosen from pixels, per lane, per draw

Three levels, each chosen from what the current window and lane rect give:

| Level | Chosen when | Drawn |
|---|---|---|
| **Regions** | a sixteenth note is under 2 pt wide | blocks in the track's colour, the pattern's name where the block is wider than its name, pass boundaries as notches, the notes as a 1 pt silhouette |
| **Notes** | otherwise | notes as bars on the lane's pitch scale, velocity as opacity, accents outlined, a drum track a row per sound in the order of its GM note |
| **Named notes** | a row is at least 9 pt tall and a note wide enough for its name | as *Notes*, plus the name on each note (`E♭4`, `kick`) and a key strip at the lane's left edge |

The pitch scale is the lane's own range — lowest to highest note of its tracks
over the whole song, padded by two semitones — not the window's, so a pan does
not rescale the rows under the reader's eyes. Thresholds are in points so a
zoomed interface (`scaled-controls`) moves them with everything else.

Cost: notes are drawn only for regions intersecting the window, found by binary
search over start-sorted regions per track; a region's notes are contiguous in
the export. Neon's 4,997 notes are well within a frame at any level, and the
silhouette at the *Regions* level is one path per region, built once per
arrangement and scaled.

### 5. Caret and clicks work through regions

The caret in a `pattern` block lights every region of that pattern — lit the
way a lane is lit now; in a `track` block, that track's regions. Clicking a
region reveals its `play` line (`file`, `line`); ⌥-click reveals the pattern's
definition. Clicking a note with nothing under a region is a seek, as a click
on a wave is now. Double-click stays unassigned, for a future edit.

### 6. The drawing is its own file

`SongPreviewView.swift` is 1,078 lines against a limit of 1,100, and
`SongCanvas.swift` 682. `SongNotesDrawing` draws one lane's arrangement into a
rect for a window and a level, and knows nothing of the pane; `SongArrangement`
is data. The pane's own additions — running the export, the caret — go into an
extension file, `SongPreviewView+Notes.swift`.

## Risks / Trade-offs

- **The export and the render can disagree** if the file changes between the
  two runs starting → both are started in the same turn, from the disk as it
  is then, and an export that lands after a newer one was started is dropped.
- **`mat` writes regions in the order of the `play` lines**, which is not the
  order they sound in when an `at` goes back — neon's `dj` plays bar 49 before
  bar 31. Regions are sorted by start to be searched, and each note's region
  index is moved with its region; found in the driven run as `dj`'s notes
  drawn past the end of the region they were clipped to.
- **Ten stem lanes at the pane's usual height are about 40 pt each**, which
  holds *Regions* and *Notes* but rarely *Named notes* → the Mix view's single
  lane and a tall pane get there; vertical zoom is the open question below.
- **A changed `mat` is needed** for regions → an older one still draws notes;
  the pane never requires a version, it draws what it gets.
- **Humanized notes stray past their region's edges** → clipped to the region
  when drawn; the region is where the source put it, which is what a reader
  wants to see.

## Open questions

- **Vertical room for *Named notes*.** Options: a lane grows when clicked
  (Logic's track zoom), or ⌥-pinch zooms rows. Looked at in the real pane on
  2026-09-18, at 1600×1000: the Mix view's twelve strips are about 80 pt each,
  and brass's range of C4 to F5 with its padding is 22 rows of under 4 pt, so
  names are reached only by a strip of few rows (`dj`'s four sounds). The
  *Named notes* level works as designed; there is not yet the room to see it
  on a melodic track. This is the one scenario of the spec it does not meet.
- **Colour per track or per pattern.** Logic colours by track. Colouring by
  pattern would show repetition — the same colour every time `chorus_melody`
  comes back — which is arguably more useful for a text-first song. Proposed:
  by track, pattern as an option, decided once seen.
