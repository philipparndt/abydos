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

## 3. Before finishing

- [x] 3.1 A paragraph in `docs/release-notes-0.22.0.md`.
- [x] 3.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
retired and its account is `openspec/specs`.
