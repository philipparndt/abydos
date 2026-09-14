## 1. The cut, without a window

- [x] 1.1 `AudioCut` in AbydosKit: marks to frames, the segments a keep or a
      delete leaves, writing them to a float CAF, saving a working copy over
      the original in its own format by replace, MP3 refused by name.
- [x] 1.2 `AudioCutTests`: frames in either order, segments, an exact join,
      nothing left refused, WAV/AIFF/CAF written back at their own depth with
      no leftovers, MP3 refused.

## 2. The tab

- [x] 2.1 `AudioFileView+Cut`: marks, the selection label, *Keep Selection*
      and *Delete Selection*, working copies, undo and redo, save, discard
      on close; `i`, `o`, `k`, `⌫`, Escape.
- [x] 2.2 `AudioCanvas` draws the band and the marks.
- [x] 2.3 The tab's `isDirty`, ⌘S and the close prompt ask a sound tab; a cut
      commits a provisional tab.
- [x] 2.4 `--audio-steps`; driven on a WAV and an M4A, recorded in the design.

## 3. Before finishing

- [x] 3.1 Release notes.
- [x] 3.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate`.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
retired and its account is `openspec/specs`.
