## 1. The analysis

- [x] 1.1 `FilePreview.Kind.audio` for `wav`, `mp3`, `m4a`, `aac`, `aif`,
      `aiff`, `flac` and `caf`, with tests beside the picture and video ones —
      and `ogg`, `opus` and `wma` staying `nil`.
- [x] 1.2 `AudioAnalysis` in AbydosKit: chunked `AVAudioFile` reading, per-
      channel min/max peaks per 256 frames, and spectrogram columns (mono mix,
      2,048-sample Hann window, hop for at most 4,096 columns, decibels via
      vDSP), cancellable.
- [x] 1.3 Tests over synthesised signals: peaks of a known ramp, the loudest
      bin of a 1 kHz tone, the column count for a long signal, and a file that
      is not audio failing with the decoder's error.

## 2. The tab

- [x] 2.1 `AudioFileView` on `DelayedPaneView`: `AVPlayer` paused at the
      start, paused again when it leaves the window, no Now Playing entry.
- [x] 2.2 The transport strip: play/pause `DrawnButton`, time label, Wave /
      Spectrum / Both `DrawnChoice`; Space plays and pauses.
- [x] 2.3 The wave: lanes per channel (mixed past two, channel count in the
      strip), drawn from the peaks at the width it has; the playhead at 30 Hz
      while playing; click and drag to seek.
- [x] 2.4 The spectrogram: a `CGImage` of the columns on a logarithmic
      frequency axis, the same playhead and seeking.
- [x] 2.5 The waiting strip until peaks, then until the spectrogram; the
      decoder's error in place of the drawing.
- [x] 2.6 `makeAudioTab`, the `.audio` cases in opening and preview, and the
      `waveform` icon in `FileIcon`.

## 3. Asked for while it was being built

- [x] 3.3 Playback through `AVAudioEngine` and an `AVAudioPlayerNode`: segments
      scheduled from the playhead, a whole pass queued behind while looping,
      the playhead from the node's sample time; engine started only on play,
      muted in a driven run.
- [x] 3.4 The loop button, lit while on, switchable while playing.
- [x] 3.5 Zoom and scroll: a window of start and span, pinch and ⌥-scroll to
      zoom around the pointer, scroll to pan, *Fit*, the position bar, paging
      with the playhead; `AudioAnalysis.read` over a range at given
      resolutions, and the region on screen read again 150 ms after it
      settles.
- [x] 3.6 Playing on when another tab is in front; stopping on close through
      the tab's teardown; the tab's speaker while playing.
- [x] 3.7 `--audio-zoom`, `--audio-loop`, `--audio-play`, `--audio-wait`, and
      the report's `loop=`, `window=` and `detail=`; driven proof of a loop's
      wrap, a zoomed region's detail, and a sound playing behind another tab;
      recorded in the design.

- [x] 3.8 Space on a sound's or a video's row plays and pauses its tab; Quick
      Look is neither the key's answer nor in the menu for a file with a tab of
      its own. A driven video is muted, as a driven sound is.

- [x] 3.9 ← and → jump five seconds, ⇧ one; wrapping while looping, clamped
      otherwise; a zoomed view follows.

- [x] 3.10 One player at a time: starting a sound or a video pauses whichever
      other was playing, across tabs and windows.

## 4. Proving it

- [x] 3.1 `--audio-report` and `--audio-seek`.
- [x] 3.2 Driven on synthesised files in the scratchpad — a stereo `.wav`, a
      1 kHz tone written as each of the eight containers (`afconvert` makes
      all but the MP3, which macOS decodes and cannot encode — `lame` writes
      that one on this machine, as a driven-run fixture only, never a build
      dependency), a ten-minute file, a `broken.wav` — with captures at 1.0 and 2.0
      of wave, spectrum and both, and each container's duration in the report;
      recorded in the design.

## 5. Before finishing

- [x] 4.1 A line in the next release's notes.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
retired and its account is `openspec/specs`.
