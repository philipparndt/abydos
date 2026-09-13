## Why

Asked for on 2026-09-13: a [musik-as-text](https://github.com/rnd7/musik-as-text)
`.song` — plain text that `mat render` turns into sound — should open the way a
`.scad` or a `.puml` does, with the thing it makes beside the text. Today a
`.song` is a text file and nothing else: to hear it somebody runs `mat play` in
a terminal, and to see whether the drums land where the grid says they do they
render it and open the `.wav` in a second tab, whose player (0.21.0) knows
nothing about the song, its bars or its tracks.

Three things were asked for, in the words of the request: the sound beside the
source like the markdown and 3D previews; the track "as a single track but
also different stems, where each channel can be enabled and disabled for
playback"; and "when selecting a track in the source the according track is
highlighted (the wave/spectrum) in the preview".

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **A `.song` opens split**, text on the left and its sound on the right, like a
  `.scad`. The pane renders the file with `mat render --stems` when it is first
  looked at and again whenever the file changes on disk, into a directory of its
  own under the temporary directory — never into the project.
- **The mix, or the stems.** A *Mix / Stems* switch in the pane's strip shows
  the whole song as one wave and spectrogram, or one lane per layer — `mat`'s
  stem groups, a track's own name unless it says `layer` — each named, with the
  tracks in it, and each with a switch that silences it. The switches change
  what is heard at once and keep the place.
- **The caret lights the stem.** With the caret in a `track` block, that
  track's lane is lit; in a `pattern` block, every lane whose track plays that
  pattern. Clicking a lane's name puts the caret on its `track` line.
- **It keeps playing across edits.** A new render takes over at the same
  playhead, playing if it was playing. A render that fails — which a save
  mid-line usually is — leaves the last sound playing and shows the error on
  a strip over it; clicking the strip reveals the line `mat` named.
- **Bars and sections.** The lanes carry the bar grid, numbered where there is
  room, and the song's `section`s along the top; the clock says which bar the
  playhead is in.
- **The same transport as a sound file.** Play and pause, Space, ← and →, a
  loop, pinch and ⌥-scroll to zoom, *Fit*, and Wave / Spectrum / Both.
- **When `mat` is not installed** the pane says so, with the `cargo install`
  line, and renders nothing.
- **Named in the tree.** A `.song` gets a notes icon in the sound files' colour.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `previews`: a new requirement beside the audio one — a song opens with its
  sound beside it, as the mix or as stems with switches, lit from the caret.

## Impact

- **AbydosKit**: `Project/FilePreview.swift` gains a `.song` kind that opens
  `.splitRight`; `Preview/SongSource.swift` (new) reads the blocks out of the
  text — tracks, layers, patterns, the block under a line; `Preview/SongRender.swift`
  (new) is the `mat` command line, the stems' `manifest.json` and the shape of a
  failed render's output. All of it pure and tested without a window.
- **AbydosApp**: `Editor/SongPreviewView.swift` (new) is the pane;
  `Editor/SongCanvas.swift` (new) draws the lanes; `Editor/AudioPlayback.swift`
  now plays several files as one, padded to the longest, with a volume per
  file — the single-file player is the same class with one voice.
  `CodeView` gains an `onCaretLine` hook beside the status bar's;
  `EditorViewController+Preview` wires the pane both ways; `FileIcon` the icon.
- **Driving**: `--song <steps>` — report, view, switches, caret, play, an edit
  of the file on disk to make the pane render again.
- **Nothing new to link.** `mat` is somebody's own install, found the way every
  tool is (`Executables.locate`).
