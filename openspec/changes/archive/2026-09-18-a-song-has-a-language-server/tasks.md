## 1. The server, in musik-as-text

- [x] 1.1 `crates/mat-lsp`: `Analysis` over the text (lines by source line,
      the song or the last one that parsed, the diagnostics); `block_at`;
      `completions` by block, kind, word index and prefix; `hover`;
      `definition`; `symbols`; `diagnostics`; UTF-16 positions.
- [x] 1.2 `docs.rs`: a line per keyword, setting, wave, filter mode, LFO
      target, drum, scratch move and sweep parameter, and the `key=`
      options a setting takes.
- [x] 1.3 `run_stdio` over lsp-server: full-text sync, publish diagnostics
      on open and change, clear them on close, answer completion, hover,
      definition and symbols, exit when told.
- [x] 1.4 `mat lsp` in `mat-cli`; `mat_core::lexer` public.
- [x] 1.5 Twelve tests over a small song, and a scripted stdio client
      proving the handshake, diagnostics, completion, hover, definition,
      symbols and exit.

## 2. Abydos

- [x] 2.1 `song` in `LanguageRegistry` (extension and name) and
      `CommentSyntax`; the `mat lsp` definition in `LanguageServers`;
      `SongLanguageTests`.
- [x] 2.2 Driven: a song with a misspelt instrument opened with `mat` on the
      PATH — the diagnostic on the line, go-to-definition from a track's
      `instrument` line to the instrument, the banner when the `mat` found
      has no `lsp`; recorded in the design. Found and fixed on the way: a
      file opened before *Trust* never reached a server.

## 2b. Where lines are heard

- [x] 2.3 `mat` b0083ad: `placement::placements` — per line, where it is heard;
      pattern events, audio steps and sections carry their line, outside the
      render cache's key; `mat/timeline` after each parse, advertised as
      `experimental.timeline`.
- [x] 2.4 Abydos: `LineTimeline` and its tests; the client hands unknown
      notifications on; the language service keeps a timeline per file; the
      gutter's bar column, its hover, and no breakpoint on a click;
      `timeline:<line>` step; driven on the shanty, recorded in the design.
- [x] 2.5 The playhead as a tick through the bars; a click on a bar seeks and a
      drag scrubs; `timeline-click:<line>:<fraction>[:<to>]` step; driven.
- [x] 2.6 Time codes, a click walking a line's repeats; both song columns as
      settings, toggled from the gutter's menu and the Editor menu; the lines
      heard marked while playing, and the notes under the playhead lit (mat
      ecdd911: passes and notes in `mat/timeline`); breakpoints stop the song
      where their line starts; `timecode-click`, `song-columns`, `break` steps; driven.
- [x] 2.7 `tree-sitter-song` in mat (d333880); vendored as
      `TreeSitterSongVendored`, registered as `song`; `aSongIsColoured`; captured.
- [x] 2.8 Includes: mat e72d7e5 and ce7deec; the grammar re-vendored; the
      manifest's `sources` fingerprinted and watched; the playhead and stops
      posted to the included files' tabs; breakpoints across files; frames in
      their files; an included file's pane kept from driving the song; driven
      and captured.
- [x] 2.10 One playback per song, borrowed by every pane of it, with the stems
      switched off kept with the song; the one-sound rule and the debugger's
      session know two panes of one song; driven.
- [x] 2.9 An included file's pane plays the song that includes it; the pane
      that is heard says where the playhead is; `panel:<points>` step.

## 3. Before finishing

- [x] 3.1 A paragraph in `docs/release-notes-0.22.0.md`.
- [x] 3.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
retired and its account is `openspec/specs`.
