## Why

**The button says "Open in Hex Editor" and opens a dump that cannot select a
byte.** `HexView` is a hundred and sixty lines whose own doc comment reads
*Read-only hex dump*: no `mouseDown`, no `keyDown`, no caret, no selection, no
find, no way to go to an offset, no way to change a byte and no way to save one.
It is reached from exactly one place — the binary notice's button, added in
commit `ab8e8934` alongside the file's size line — and from nowhere else, so a
text file can never be looked at as bytes at all. Nothing in `openspec/specs`
describes it and nothing in `Tests` exercises it; it is the one editor in this
app with neither.

What it does well is the one thing it was built for: the file is memory mapped
and only the visible rows are formatted, so a 114 MB STL opens at once and
scrolls at full speed. That is the foundation, and everything below keeps it.

Asked for on 2026-09-06: "the current hex editor is only a viewer and by far
not complete. It not even supports selection, search for bytes, ... I want to
enhance this to a full hex editor with entropy analysis, minimap, structured
explanation of known binary formats, embedded AI analysis (claude code is asked
to provide infos for the structured explanation), checksums, everything else
that is nice in a modern hex editor".

No originating backlog item: asked for directly, and the backlog is closed.

## What Changes

- **A caret and a selection**, in both the hex column and the text column,
  from the pointer and from the keyboard, with the status bar saying the offset
  and the selection's length the way it says line and column for text.
- **Bytes can be searched**: a hex pattern with `??` wildcards, text in a
  chosen encoding, or a number in a chosen width and endianness — through the
  find bar the editor already has, with the matches marked on the minimap. A
  search over a gigabyte runs in chunks off the main thread, says how far it
  has got, and can be stopped.
- **Bytes can be edited and saved.** Overwrite is the default and insert is a
  mode that is shown while it is on. Typed nibbles, typed characters, paste,
  delete, undo and redo; edited bytes are marked until the save; ⌘S writes the
  file through a temporary and a rename; a byte document is **never
  auto-saved**, because half a typed nibble written into a Mach-O is a
  corrupted binary rather than a draft.
- **Copy in the shapes a hex editor is asked for**: as hex, as text, as a C
  array, as base64; paste of hex text or raw bytes.
- **Go to an offset**, hex or decimal, absolute or relative to the caret.
- **An inspector beside the bytes** says what the bytes at the caret are —
  integers of every width in both byte orders, floats, a character, a Unix
  time, LEB128, binary — and lets a value be typed over, which writes the bytes.
- **Checksums** of the file or of the selection: CRC-32, Adler-32, MD5, SHA-1,
  SHA-256, SHA-512. Streamed, so the file is never read into memory to hash
  it; copyable; marked stale the moment a byte changes.
- **Entropy**, in blocks sized from the file, drawn as a curve with the
  viewport marked on it; a region above 7.5 bits a byte is named as likely
  compressed or encrypted rather than left to be read off a graph.
- **A minimap**: the whole file in one strip, each row of pixels a block
  coloured by what its bytes are — zero, printable, control, high — or by its
  entropy, with the viewport, the matches and the edited ranges drawn on it,
  and click and drag to move.
- **Known formats explained**: a file whose magic is recognised gets a tree of
  its fields — name, offset, length, meaning — that selects bytes when a row is
  chosen and names the field the caret is in. Built in: PNG, JPEG, GIF, BMP,
  ZIP (and what is a ZIP under another name: JAR, 3MF, DOCX), gzip, tar, ELF,
  Mach-O including fat, PE, SQLite, RIFF/WAV, Java class, WebAssembly. A
  truncated or malformed file stops the tree where it broke and says so.
- **Claude can be asked**, through the `claude` command the commit page already
  uses and never the API: what a file is, or what a selection is. It is sent a
  bounded sample — the head, the tail, the selection, the entropy summary and
  what the built-in parser found — and answers in a shape that becomes rows in
  the same tree, drawn as Claude's and never as parsed fact. It cannot change a
  byte. Absent when there is no `claude`, as the commit draft is.
- **Strings**: printable runs listed, each a jump.
- **Two more doors.** Any file can be opened as hex from the tab's menu and the
  palette, text files included; a hex tab over a file that is text can go back.
  The binary notice stays the door for binaries, for the reason its size line
  exists: a gigabyte of video is not something to dump by default.
- **The view is driveable**: a `--hex` step string and a report, so the
  screenshots and the proof are made the way the refs tree's are.
- **Not proposed:** a scripting or pattern language for formats, structure
  templates loaded from files, comparing two binaries, disassembly, or
  editing files larger than the machine's address space.

## Capabilities

### New Capabilities

- `hex-editor`: what a file looked at as bytes can do — selection, search,
  editing and saving, copy shapes, going to an offset, the inspector, checksums,
  entropy, the minimap, the structure of known formats, the ask to Claude,
  strings, the doors in and out, and what all of it costs on a large file.

### Modified Capabilities

<!-- None. No existing spec describes the hex view; `previews` mentions the
binary notice only to say it is kept for a video the system cannot play, and
that stays true. -->

## Impact

- `Sources/AbydosKit/Hex/` — new, and the whole of the engine: `ByteDocument`
  (the mapped file plus its edits as pieces, undo, save), `ByteSearch`,
  `ByteValues` (the inspector's readings and writings), `ByteStatistics`
  (entropy and byte classes in one pass, shared by the curve and the minimap),
  `Checksums`, `BinaryFormat` and the parsers under it, `HexAnalysis` (the ask
  to Claude, in `ClaudeDraft`'s shape), `PrintableStrings`. None of it holds a
  view, so all of it is tested without a window.
- `Sources/AbydosApp/Hex/` — new: the editor view split across files the way
  `EditorAreaController+Driving` splits, the minimap, the bar above the bytes,
  the inspector pane, and a controller assembling them into the tab.
  `Sources/AbydosApp/Editor/HexView.swift` is removed.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — `Tab` gains the byte
  document beside the text one, and `isDirty`, `save()` and the close prompt
  learn to ask it; the find bar gains a byte mode; the notice's button and the
  new menu and palette actions open the controller. The file is already the
  largest in the repository, so what goes in it is the wiring and no more.
- `Sources/AbydosApp/LaunchOptions.swift` — `--hex` steps and their report.
- Tests: one suite per subject under `Tests/AbydosKitTests`.
- No new dependency: CryptoKit is in the platform and already imported by the
  kit; CRC-32 and Adler-32 are twenty lines each; Claude is reached through the
  command that is already reached.
