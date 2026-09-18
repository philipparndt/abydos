## Why

Asked for on 2026-09-14, while the song pane was being tried: "support i + o
keys to make a selection and be able to keep only the selection or delete the
selection from a audio file". A sound tab plays, zooms and loops a file, and
the one thing that follows from listening — the loop is two bars too long, the
take has a cough at 0:41 — sends somebody to another application and back.

There is no originating `.abydos/backlog` item: the backlog is retired and
this comes from a direct request.

## What Changes

- **`i` and `o` mark a selection** at the playhead: the in-point and the
  out-point, in either order. The selection is drawn across the wave and the
  spectrum, and Escape clears it.
- **Keep or delete it.** *Keep Selection* (`k`) leaves only the selection;
  *Delete Selection* (`⌫`) takes it out and joins what was either side. Cuts
  are sample-accurate and add no fades.
- **Nothing is written until ⌘S.** A cut renders into a working copy, the tab
  shows the edited dot, ⌘Z and ⇧⌘Z step through cuts, and closing the tab asks
  whether to save. ⌘S writes the file in its own format, over itself, in one
  replace.
- **A selection is written to a file of its own.** *Save Selection As…* (`s`)
  writes the selected stretch to a new file in the source's own format, leaving
  the recording untouched, and offers a name carrying where it starts —
  `session two 1-23.250.wav`. Asked for 2026-09-16.
- **`ii` and `oo` carry a selection on.** A second `i` moves the start to where
  the selection ended and lets the end go, so the next selection begins where
  the last one finished; `oo` is the mirror. Cutting a recording into samples
  is then mark, write, `ii`, play on, mark. Asked for 2026-09-16.
- **What cannot be written says so.** macOS has no MP3 encoder: an MP3 is cut
  and played as any file is, and ⌘S says it cannot be saved as MP3 and keeps
  the edit.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `previews`: the sound-file requirement gains a selection and two cuts.

## Impact

- **AbydosKit**: `Preview/AudioCut.swift` (new) — the selection's frames, the
  segments a cut keeps, writing them to a working copy and a working copy over
  the original, all without a window and tested on synthesised files.
- **AbydosApp**: `AudioFileView` gains the marks, the keys, the buttons, the
  working copy and its undo; `AudioCanvas` draws the selection; the tab's
  dirty state, ⌘S and the close prompt learn about a sound tab.
- **Driving**: `--audio-steps` — marks, cuts, undo, save and the report.
