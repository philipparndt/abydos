## Why

Asked for on 2026-09-13: a `.wav` or an `.mp3` in a project should play, show
its wave, and show its spectrum, the way a video already plays in a tab. Today
`FilePreview.kind` has no case for either, so both fall through to the binary
notice — "This looks like a binary file", a hex editor and a Quick Look button
whose panel belongs to no tab. That is the fault the video requirement was
written against, and sound is the half of it that was left over.

There is no originating `.abydos/backlog` item: this comes from a direct
request, and that backlog is retired in favour of `openspec/changes`.

## What Changes

- **An audio tab.** A `.wav`, `.mp3`, `.m4a`, `.aac`, `.aif`, `.aiff`, `.flac`
  or `.caf` — every audio container the system decodes natively — opens in the
  editor area as a player,
  paused at the start, with no document and no dirty state — a tab shaped
  like a video's. It plays only when play is pressed. Unlike the video, it
  keeps playing when another tab is brought to the front, and stops when its
  own tab is closed; while it plays out of sight, its tab carries a speaker.
- **The wave.** The file's waveform, one lane per channel for mono and
  stereo, drawn across the tab with a playhead. Clicking or dragging on it
  moves the playhead; the wave is the timeline, not a picture beside one.
- **The spectrum.** A spectrogram of the whole file — time across, frequency
  up on a logarithmic scale, loudness as colour — under the wave or instead of
  it, chosen by a switch in the tab's strip, sharing the wave's playhead and
  timeline.
- **A loop.** A loop button in the strip plays the file round and round with
  no gap at the seam, and can be switched on or off while it plays.
- **Zoom and scroll the timeline.** Pinch, or ⌥-scroll, zooms the wave and the
  spectrogram together around the pointer; scrolling pans; *Fit* shows the
  whole file again. Zoomed in, the region on screen is read again at the
  detail the width allows, so the wave and the spectrum sharpen rather than
  stretch.
- **Read once, off the main thread, and only when looked at.** Decoding and
  the frequency analysis run in the background when the tab is first shown,
  under the waiting strip every pane has, and a long recording is reduced to
  what a tab can draw rather than held whole.
- **Named in the tree.** The audio extensions get a sound icon.
- **What the system cannot decode stays as it is.** `.ogg`, `.opus` in an
  Ogg container, and `.wma` keep the binary notice and its Quick Look, the way
  a `.webm` does beside the video tab.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `previews`: a new requirement beside *A video opens as a player, silent
  until asked* — audio in any natively decoded container opens as a player
  with its wave and its spectrum.

## Impact

- **AbydosKit**: `Project/FilePreview.swift` gains an `.audio` kind;
  `Preview/AudioAnalysis.swift` is new — decoding to peaks and to spectrogram
  columns, pure where it can be so it is tested without a window. It uses
  AVFoundation to decode and Accelerate's vDSP for the FFT, both system
  frameworks: no new package dependency.
- **AbydosApp**: `Editor/AudioFileView.swift` is new — the player, the wave,
  the spectrogram, the transport strip; `EditorViewController+Opening.swift`
  and `+Preview.swift` make the tab; `Navigator/FileIcon.swift` the icon.
- **Driving**: `--audio-report`, beside `--video-report`, printing what the
  tab decoded and where the playhead is.
