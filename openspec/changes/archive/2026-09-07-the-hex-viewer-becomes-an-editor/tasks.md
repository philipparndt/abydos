## 1. The document

- [x] 1.1 `Sources/AbydosKit/Hex/ByteDocument.swift` — the mapped original
  and a piece table over it: `byte(at:)`, `bytes(in:)`, `count`, `overwrite`,
  `insert`, `delete`, each a split of the piece list and never a copy of the
  file. An append-only buffer holds typed and pasted bytes. `isDirty`, and the
  edited ranges for the marks.
- [x] 1.2 Undo as the piece list before the edit, registered on an undo
  manager the caller supplies, so the window's ⌘Z reaches it.
- [x] 1.3 `save()` streams the pieces to a temporary beside the original,
  renames it into place and re-maps; the comment names the half-old-half-new
  file a write over one's own mapping produces. `autoSaveIfNeeded` is false by
  construction, with the corrupted-Mach-O reason beside it.
- [x] 1.4 `Tests/AbydosKitTests/ByteDocumentTests.swift` — overwrite, insert,
  delete, undo, save-and-reopen byte-for-byte, and *a one-byte edit to a large
  file costs bytes* measured on a fixture generated under the scratchpad.

## 2. Reading and finding bytes

- [x] 2.1 `ByteValues.swift` — the inspector's readings from an offset in a
  byte order: the integers, the floats, the character, the two Unix times,
  LEB128, binary; `nil` where fewer bytes remain than the reading needs. And
  the writings: a value to bytes in an order, through the document's
  `overwrite`.
- [x] 2.2 `ByteSearch.swift` — a `Pattern` of bytes and a wildcard mask, made
  from a hex string with `??`, from text in an encoding, or from a number in
  a width and order; the hex parse rejects half a byte with a sentence. A
  chunked scan with `memchr` on the first fixed byte, overlapping by the
  pattern's length, delivering matches as it goes on an `AsyncStream`, with
  progress and cancellation.
- [x] 2.3 `PrintableStrings.swift` — runs of four or more printable bytes in
  an encoding, capped at a written count, off the main thread.
- [x] 2.4 Tests for each: the ZIP wildcard case, the number in both orders,
  the match across a chunk boundary, the half-byte complaint, the readings at
  the end of the file, the time reading 2023-11-14 22:13:20 UTC.

## 3. Statistics and checksums

- [x] 3.1 `ByteStatistics.swift` — one sequential pass producing, per block,
  entropy and the four class counts, with the block size chosen so the file
  yields about four thousand blocks; delivered block by block; blocks
  invalidated by range on an edit and only those recomputed.
- [x] 3.2 The note: runs of blocks above 7.5 bits named as likely compressed
  or encrypted with their range.
- [x] 3.3 `Checksums.swift` — CRC-32 and Adler-32 written here, the four
  digests through CryptoKit, all streaming the document's pieces with progress
  and cancellation.
- [x] 3.4 Tests: the empty file's SHA-256, a known CRC-32, the pass on a
  scratchpad-generated file of text then gzip producing low-then-high and one
  note, an edit recomputing one block, and the timing of the pass on a large
  file said through `Stopwatch.maySay` with `MachineLoad.said`.

## 4. Formats

- [x] 4.1 `BinaryFormat.swift` — the protocol, `ByteReader` with typed reads
  in either order that produce a *truncated at* node rather than reading past
  the end, and `StructureNode` with its `source`. `recognise(_:)` over the
  head returns the parser or nothing; a ZIP under another extension is named
  by the extension.
- [x] 4.2 `Hex/Formats/` — one file each: PNG, JPEG, GIF, BMP, ZIP, gzip,
  tar, ELF, Mach-O with fat, PE, SQLite, RIFF/WAV, Java class, WebAssembly.
  Repeated sections capped at a written count with a node saying how many
  were not listed.
- [x] 4.3 `Tests/AbydosKitTests/BinaryFormatTests.swift` — a small fixture per
  format, generated in the test where a generator is short and checked in
  under `Tests/Fixtures/Hex` where it is not; the PNG's IHDR fields by name;
  the truncated ZIP's node; the JAR named *JAR (ZIP)*; the field at an offset.

## 5. The ask to Claude

- [x] 5.1 `HexAnalysis.swift` — `ClaudeDraft`'s executable search reused
  rather than copied (moved to a shared place if it will not share), the
  bounded sample assembled from the document, the statistics, the strings and
  the parsed tree, the prompt asking for a paragraph and rows, the parse of
  the answer into `StructureNode`s marked `.claude` with out-of-range rows
  dropped, and the run on stdin off the main thread with cancellation.
- [x] 5.2 Tests: the sample never exceeds its budget on a large file, the
  parse of a good answer, of a fenced one, of one with a row past the end, and
  *absent without the command* against an empty `PATH` and nowhere else to look.

## 6. The editor view

- [x] 6.1 `Sources/AbydosApp/Hex/HexEditorView.swift` — the drawing from
  `HexView` kept as it is, over a `ByteDocument` instead of a `Data`, with the
  edited marks in `gitModified`, the selection in `selection`, the matches in
  the search colours and the active column told from the mirror. Bytes per row
  from the bar.
- [x] 6.2 `HexEditorView+Selection.swift` — caret and selection from the
  pointer and the keyboard as the spec lists them, the status bar's offset and
  length reported through the same path the text editor reports line and
  column.
- [x] 6.3 `HexEditorView+Editing.swift` — nibble and character typing,
  overwrite and insert, Delete's two behaviours, paste of hex text and raw
  bytes, the four copy shapes on the edit and context menus, ⌘C by active
  column.
- [x] 6.4 `HexBar.swift` — the strip above the bytes: the offset field for
  ⌘L with hex, decimal and relative and the past-the-end sentence, bytes per
  row, the insert badge, the text column's encoding.
- [x] 6.5 `HexEditorController.swift` — replaces `HexViewerController`:
  assembles the bar, the editor, the minimap and the inspector split, owns the
  statistics task, and cancels everything on close. `HexView.swift` deleted.

## 7. The minimap and the inspector

- [x] 7.1 `HexMinimap.swift` — the strip from the statistics, class colours
  or entropy on a switch, the viewport, match and edit ticks, click and drag,
  drawn from a cached picture remade on delivery and resize and never per
  scroll.
- [x] 7.2 `HexInspectorPane.swift` — the values with their byte-order switch
  and editable fields writing through `ByteValues`, the six checksum buttons
  with progress, stop, copy and the stale greying, the entropy curve with the
  viewport and the notes, the strings list with its filter. Collapses and
  remembers it.
- [x] 7.3 `HexStructureOutline.swift` — the tree as an `NSOutlineView`, a row
  selecting its bytes, the caret's field named above the bytes, the *Claude
  says* heading in its own weight, *Ask Claude* absent without the command,
  the ask's in-flight state, the failure in the command's words, *Show what
  was asked*.

## 8. The tab and the doors

- [x] 8.1 `EditorViewController` — `Tab.bytes`, `isDirty` asking either
  document, `save()` dispatching, the close prompt following; the find bar's
  byte mode with its three query kinds, progress and the half-byte complaint,
  routed to `ByteSearch` and its matches to the view and the minimap.
- [x] 8.2 The doors: the notice's button opening the controller, *Open as
  Hex* on the tab menu, in the File menu and through it in the palette, and
  on the project tree's context menu for any file row (asked for on
  2026-09-06: "it should be possible to open every file in the hex editor
  (context menu action)"); *Open as Text* on a hex tab over a file the binary
  test passes.
- [x] 8.3 Insert mode turned off when the tab is left.

## 8a. The other agent's findings, and the zoom

- [x] 8a.1 Reviewed on 2026-09-06 after a handover: the inspector's values in
  four bands with a box drawn only under the pointer or the keyboard, one
  `ChecksumRow` shape for every state (a row that has computed nothing shows
  no bar and no copy), section headings with a rule, Claude's prose folded
  behind a toggle, and the find field no longer moving as the match index
  grows. All of it compiled as written.
- [x] 8a.2 The hex editor follows the zoom: `HexEditorView`, `HexBar`,
  `HexMinimap`, `HexInspectorPane` and its `SectionHeading`, `ValueField`
  and `ChecksumRow`, and `HexStructureOutline` conform to `ScaleFollowing`,
  register in their own initialisers, and re-take fonts, heights (through
  `ScaledHeights`) and spacing in `applyTheme`. The ten `controlSize` uses
  are gone; the two search fields are `ScaledSearchField`s.

- [x] 8a.3 The entropy curve has a hover: a line under the pointer, a dot on
  the curve and the entropy there as a number with its byte range (asked for
  on 2026-09-06: "the entropy shall have a hover line that shows the entropy
  as a number"). `entropy-hover:<fraction>` drives it.

- [x] 8a.4 The structure outline from the keyboard (asked for on 2026-09-06:
  "in the structure view it should be possible to navigate with the
  keyboard. Not sure if the tree is even getting the focus"): the app's
  `TreeRowView` so the selection says whether it has the keyboard, the
  selection kept by path across the re-parse that follows every pause in
  typing — which is what had been dropping it — and Return, Enter or Space
  jumping to the row's bytes. `structure-click:<row>`,
  `structure-focus` and `structure-key:<arrow|return>` drive it through
  `TreeKeys`. Driven: from the tree's first row, ↓ selected *signature* and
  the status read `0x0–0x7 · 8 bytes`, ↓ again *IHDR*, → opened it, ↓
  *length*, and Return put the keyboard in `HexEditorView` with `0x8–0xB`
  selected. The synthetic click reported `key=false`: the driven window did
  not become key in this environment, so an activating click is swallowed
  before any view sees it — the instrument, not the tree, and why the
  `focus` step exists, as it does for the changed-file list. Two real faults
  were found on the way and fixed: activation put the keyboard on the tab's
  stack view rather than the bytes, and the outline's cells were attributed
  labels, which are selectable and take the press.
- [x] 8a.5 The entropy curve moves the editor (asked for on 2026-09-06: "it
  should be possible to scroll in the entropy view"): a click or drag jumps
  to that part of the file, a sideways wheel pans through it, and up and
  down still scroll the pane.

- [x] 8a.6 The session remembers a hex tab (asked for on 2026-09-06: "The
  hex editor should be remembered in the session file (that it is opened for
  a file, its position, the claude content, ...)"): `ProjectSession.HexState`
  under the file entry's `hex` key — caret, rows, encoding, order, and
  Claude's summary, fields and prompt — written and read by `SessionStore`,
  captured from the tab and restored into it after the file is reopened.
  `ProjectSessionTests` round-trips it; `--hex "…,session"` reports the
  capture and restores it into the same tab.

- [x] 8a.7 The curve reads a window, not a block (found on 2026-09-07 from a
  screenshot: the hover said *3.88 bits* over a file the note called *7.86
  bits a byte*, both correct — sixteen-byte blocks cannot read above four
  bits). The pass keeps a running kilobyte window behind each block, warmed
  from the blocks before a mid-file pass; the curve, the minimap's entropy
  mode, the hover and the driver's mean read it. Two tests pin it.

- [x] 8a.8 Every inspector section folds on its heading (asked for on
  2026-09-07: "all sections should be collapsible (structure, values,
  ...)"), the shut ones kept in `Settings.hexInspectorShutSections` as a
  preference. `fold:<section>` drives it.

## 9. Proving it

- [x] 9.1 `LaunchOptions` — `--hex <steps>` and its report, in
  `--branch-rows`' shape, with `HexEditorController+Driving.swift` doing the
  steps. `ask` against a fake `claude` first on the run's `PATH` under the
  scratchpad, never the real one.
- [x] 9.2 Driven on 2026-09-06 over a scratch project under the scratchpad
  (`--open <copy> --trust --panel-maximize 1 --file <abs> --hex "…"`, a
  throwaway bundle id, an unpinned UUID, the defaults under that id); the
  files were made by a script from each format's definition, `ls.macho` is a
  copy of `/bin/ls`, and the gigabyte was a sparse file removed afterwards:
  - *PNG:* `goto:0x10,select:4,order:big,inspect` — status `0x10–0x13 · 4
    bytes`, UInt32 big-endian `16`, field *IHDR › width*; at 0x14 the label
    reads *IHDR › height*. The tree lists signature, IHDR with its fields,
    tEXt with keyword and text, IDAT, IEND.
  - *ZIP wildcard:* `find:50 4B ?? 04` over a three-entry archive — `1 of 3
    matches at 0x0 0x2B 0x5D`, `next` selects four bytes at 0x2B, three ticks
    on the minimap, viewport `0..<256`.
  - *Overwrite, save, reopen:* `goto:0x10,type:FF,type:EE,save` — `dirty=false`
    after the save, `xxd` reads `ffee` at 0x10, `cmp` against the original
    differs at byte 17 and nowhere before it.
  - *Insert and undo:* `insert,type:41` grows the file by one and marks
    `0x0+1`; `delete` takes it back; `type:42,undo` restores the bytes.
  - *Truncated ZIP:* two entries, then `local file header 3` holding
    *truncated at 0x6F in local file header 3: compressed size runs past the
    end* as a problem node.
  - *JAR:* the root reads *JAR (ZIP)*.
  - *Mach-O:* `/bin/ls` explained as a fat header with x86-64 and arm64
    slices, each with its header and load commands; the minimap shows the
    slices as bands.
  - *Text file as hex:* `notes.txt` opened as bytes; `copy:hex` gave
    `70 6C 61 69 6E`, `copy:base64` `cGxhaW4=`, `copy:carray` `{ 0x7A }`;
    `paste:de ad 0xBE 0xEF` overwrote four bytes.
  - *Entropy:* a text header over a compressed tail — one note, *0x3000–0x7FFF
    is likely compressed or encrypted (7.90 bits a byte)*.
  - *Stale digests:* CRC-32 and MD5 of the whole file, then a byte typed at
    0x100 — both read *stale: …*; a CRC-32 and SHA-1 over sixteen selected
    bytes elsewhere stood.
  - *The fake Claude:* a `claude` script first on the `PATH` answering a fixed
    summary and three rows, one past the end — the summary and two rows under
    *Claude says*, each `[claude]`, the third dropped, prompt 997 characters.
  - *The gigabyte:* `goto:0x3FFFFFF0` shows the last row, `find:01` finds the
    one match at 0x3FFFFFFF, the pass finishes 4096 blocks of 256 KB,
    SHA-256 reads `769e8133…0676a4` and `shasum -a 256` agrees, the minimap's
    viewport is the last 272 bytes — all within the run's forty seconds with
    the editor answering throughout.
  - Screenshots under the scratchpad: `hex-png.png`, `hex-zip.png`,
    `hex-macho.png`, `hex-edit.png`, `hex-stale.png`, `hex-ask.png`.
- [x] 9.3 The timing claims print their load: the 128 MB statistics pass at
  1.8–1.9 s in a debug build (`load 5.6–10.1 over 10 cores`), bounded only
  under `make timing`; the 256 MB one-byte edit grew the process by 32 KB.

## 10. Finishing

- [x] 10.1 `Scripts/file-size-allowed.txt` raised for what grew:
  `EditorViewController.swift` 5869 → 5960 (the tab's `hex`, the three doors,
  `showHexEditor`, the status text, the driver), `LaunchOptions.swift`
  1641 → 1644 (`--hex`), `AppDelegate.swift` 3902 → 3919 (two menu items,
  ⌘L, the dispatch). Every new file is under a thousand lines; the largest is
  `HexEditorController.swift` at 610.
- [x] 10.2 `docs/release-notes-0.15.0.md` has the section.
- [x] 10.3 No `.abydos/backlog/spec/*.md` is made untrue: that directory is
  gone from the tree, and the spec it kept never described the hex view.
  Two deviations from the design, recorded in the spec and in the code: a
  digest over a selection an edit did not touch is kept rather than marked
  stale, and the "byte mode" is the hex tab's own bar rather than a mode of
  the editor's find bar, for the reason `HexBar` gives.
- [x] 10.4 Green by their exit codes on 2026-09-07, after the curve's window
  and the folds: `make test` 4217 tests in 534 suites, exit 0 with the
  suite's two standing known issues, load 49.3 over 10 cores; `make
  warnings` exit 0, *No warnings in this repository's Swift*.
