## Why

Asked for on 2026-09-18: "I think we should add another visualization for the
users that are used to logic and co: add patterns and notes of cause this
requires a appropiate zoom level".

The song pane shows what a song *sounds* like — a wave and a spectrogram per
stem — and nothing of what it is *made of*. Somebody coming from Logic,
GarageBand or Ableton reads a song as regions on tracks and notes inside them,
and the pane gives them no way to see that the chorus is `brass` played four
times from bar 33, or that the hook's third note is an E♭. The source says so,
but spread over a file: in `examples/neon.song` the `pattern` blocks are on
lines 48–180 and the `track` blocks that place them on lines 181–412, and which
bar a given `play` lands on is arithmetic over the `at`, `rest` and `repeat`
lines before it.

`mat` already works all of this out. `mat export examples/neon.song` takes
14 ms and gives every track's notes in seconds — 4,997 of them for neon,
drums by name — but not the patterns they came from: `arrange.rs` resolves each
`play <pattern>` into notes and drops the placement, so regions cannot be drawn
from it today.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **In musik-as-text (`mat`), on its `main`:** `mat export` gains a `regions`
  list per track — each `play` as one region with its pattern's name, its start
  and end in seconds, the length of one pass, its `repeat` and `transpose`, and
  the file and line it was written on and the pattern was defined on. Each note
  says which region it came from. Audio clips become regions too. Additive: a
  reader of today's JSON is unaffected.
- **A fourth drawing mode, *Notes*,** beside *Wave*, *Spectrum* and *Both*. It
  draws each lane as an arrangement: the regions of the tracks in that lane as
  coloured blocks named by their pattern, and the notes inside them.
- **What is drawn follows the zoom.** Zoomed out to the whole song, a region is
  a block with its name and a silhouette of its notes. Closer, the notes are
  bars on a pitch scale, drums a row per sound. Closer again, where there is
  room, each note carries its name and the lane a key strip. Velocity shows as
  strength of colour.
- **It takes part in what the pane already does.** The playhead, the bar grid,
  sections, the loop and the pan and zoom are the same over notes as over
  waves. The caret in a `pattern` block lights that pattern's regions; clicking
  a region puts the caret on the `play` line that placed it.
- **It is there before the sound is.** The arrangement comes from `mat export`,
  run beside every render. A song that fails to arrange keeps the last
  arrangement drawn, the way a failed render keeps the last sound.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `previews`: new requirements beside *A song opens with its sound beside it* —
  a song can be shown as its patterns and notes, drawn at the detail the zoom
  allows, lit from the caret and revealing its source.

## Impact

- **musik-as-text** (`~/dev/musik-as-text`, committed to its `main` as the
  user agreed on 2026-09-18): `crates/mat-core/src/arrange.rs` keeps the
  placements (`TimelineRegion`, and a region index on `TimedNote`); the export
  serialises them; a test in `mat-core` that the regions of a song cover its
  notes. `docs/` says what `regions` is.
- **AbydosKit**: `Preview/SongArrangement.swift` (new) — the `mat export`
  command line and the decoding of the part of its JSON the pane draws, tracks,
  regions and notes, ignoring instruments and master. Pure and tested.
- **AbydosApp**: `Editor/SongNotesDrawing.swift` (new) draws one lane's
  arrangement at a level of detail chosen from the zoom; `SongCanvas` gains the
  mode and hands a lane's rect to it; `SongPreviewView` runs the export beside
  the render and wires caret and clicks. `SongPreviewView.swift` is at 1,078
  lines of the 1,100 `source-file-size` allows, so what this adds to the pane
  goes in a collaborator of its own, not into it.
- **Driving**: `--song` gains `notes` (the mode) and a report of the regions and
  notes on screen and the level of detail drawn, so a zoom can be checked in
  words.
- **No `.abydos/backlog/spec` file is made untrue**: the backlog is retired.
