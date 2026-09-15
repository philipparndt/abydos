## 1. Reading the song and the render

- [x] 1.1 `FilePreview.Kind.song` for `.song`, opening `.splitRight` with
      every mode offered, with tests beside the audio ones.
- [x] 1.2 `SongSource` in AbydosKit: blocks at column one, `layer`, `mute`
      and `play` under a track, the block under a line, and the layers a
      caret lights; tests over a shortened `drunken-sailor.song`, comments,
      a file being typed.
- [x] 1.3 `SongRender` in AbydosKit: the command line, `manifest.json` as
      `mat` writes it (layers, tracks, tempo, meter, bar length, sections,
      the bar a moment is in), the `error: … --> file:line:col` shape and
      its hint, the complaint for a silent failure, the `rendered …` line;
      tests against output measured from the tool.

## 2. The pane

- [x] 2.1 `AudioPlayback` over several files: a node per file, one start
      time, silence padding to the longest, a volume per voice; the one-file
      player unchanged in behaviour.
- [x] 2.2 `SongCanvas`: lanes with headers, switches and a light; wave and
      spectrum per lane from `AudioCanvas`'s statics; one window, playhead,
      pinch, ⌥-scroll and pan; bar lines numbered where there is room, the
      sections along the top, the position bar.
- [x] 2.3 `SongPreviewView` on `DelayedPaneView`: `mat` located or the
      install line shown; the render into a fresh `run-<n>` under the
      temporary directory, the watch and the fingerprint, a run in flight
      replaced, the 300 s deadline; the take-over of playhead, loop and
      playing; the previous run deleted; the strip with play, loop, the
      clock with the bar, the info line, *Mix / Stems*, *Fit* and
      Wave / Spectrum / Both; the error strip that reveals the line; Space,
      ← and →; one player at a time; teardown with the tab.
- [x] 2.4 The wiring: the `.song` case in the preview, the caret hook
      (`CodeView.onCaretLine`), the lane's name revealing the track, the
      speaker on the tab while it plays, the pane found for the driver
      through the area controller, the tree's icon.

## 3. Proving it

- [x] 3.1 `--song <steps>`: report, wait, mix, stems, wave/spectrum/both,
      on/off, caret, play, loop, seek, edit, rendered.
- [x] 3.2 Driven on a copy of musik-as-text's examples under the scratchpad,
      with `mat` on the run's `PATH`: the render landing and its stems; the
      caret in a track and in a pattern lighting lanes; a stem switched off;
      an edit of the file re-rendering with the playhead kept; a broken edit
      leaving the sound and showing the strip; `neon.song`'s ten layers and
      sections at 2.0; no `mat`; captures of the stems and the error strip at
      1.0 and the mix at 2.0; recorded in the design.

## 3b. Asked for while it was being tried

- [x] 3.3 The last render per song kept for the next pane (`SongRenderCache`);
      `mat render --cache`, the layers' keys, drawings reused by key.
- [x] 3.4 A press on a lane's switch that drags does not seek; `wobble:`.
- [x] 3.5 Stems started on one sample time of the output's clock, measured
      with a noise file and its inverse; `drift=` removed.
- [x] 3.6 Export ▸ the mix, or the mix and stems, as WAV, FLAC or M4A beside
      the song; asks before replacing; formats asked of `mat render --help`;
      `export:` and `export-menu` steps; driven, the three files checked with
      `afinfo`.

## 4. Before finishing

- [x] 4.1 `docs/release-notes-0.22.0.md`.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

## 5. The song as a program in the debugger

- [x] 5.1 mat 774797f: the timeline's `tracks`, with each play step.
- [x] 5.2 `DAPClient` in-process transport; `DebugAdapters.song`;
      `DebugSession.startInProcess`, `thread` and `abydos/stackMoved` events.
- [x] 5.3 `SongDebugAdapter` and its tests; `LineTimeline.tracks`.
- [x] 5.4 The window starts a session when a song plays and tells it the
      pane's stops; `debug` steps; driven and captured.
- [x] 5.5 The Stack as a tree: `CallTree` and its tests, `CallStackOutline`,
      the session's stacks per open thread; the song adapter's parents, subtle
      lines and stems; driven and captured.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
retired and its account is `openspec/specs`.
