## Context

`HexView` maps the file with `Data(contentsOf:options: .mappedIfSafe)`, keeps
sixteen bytes to a row, and in `draw` formats only the rows the dirty rect
covers. That is the one design decision it made and it is the right one: a
114 MB STL opens instantly, and nothing is converted to a string up front.
Everything else is absent. It is reached from `FileNoticeView.onOpenHexEditor`
through `showHexEditor(for:)`, which swaps the notice tab's `contentView` for
the dump's scroll view and marks the tab non-provisional; the tab has no
document, so `isDirty`, `save()` and the close prompt know nothing about it.

Around it the app already has most of the parts a hex editor borrows:

- `FindBar` is a strip above the editor with a query, options, a count and a
  replace row, and each `Tab` carries its own `FindState` so switching tabs
  does not point one file's offsets at another's view.
- `ClaudeDraft` runs `claude -p` with the prompt on stdin, finds the command
  off the `PATH` and in the per-user places a Finder-launched app cannot see,
  and is *absent* rather than failing when there is no command. Its comment
  says why the API was not used: a dependency and a credential path for a
  feature that has neither.
- `MCPServer` is a loopback Streamable HTTP server the review session hands to
  an agent so the agent can call back into the app with typed data.
- `Theme.current` has the editor's colours — `editorBackground`, `editorText`,
  `gutterText`, `selection`, `searchMatchBackground`,
  `searchMatchCurrentBackground`, `gitAdded`, `gitModified` — and the scaled
  metrics the zoom work made every control read.
- `--branch-rows <steps>` is the shape of a driven proof: a step string, a
  report printed, and the sheet left undriven because `NSAlert` wants a person.
- `Scripts/file-size-allowed.txt` holds the line count of every file already
  over eleven hundred, and `EditorViewController.swift` is at 5869.

The constraints that matter: no view code in `AbydosKit`; cost written down for
anything per frame, per keystroke or per row; no dependency without a written
reason; and the file must stay a mapping, because that is what makes the large
file case work at all.

## Goals / Non-Goals

**Goals:**

- Selection, search, editing, saving, copy shapes and go-to-offset: the
  features without which the word *editor* on the button is untrue.
- An inspector, checksums, entropy, a minimap, structure for known formats,
  strings, and the ask to Claude — each as a kit type with tests and a view
  that only draws what the type says.
- A gigabyte file opens as fast as the viewer opens it today, scrolls at full
  speed, and every whole-file computation runs behind the editor and can be
  stopped.
- Every part is driveable from the launch options, so the proof is a report
  and a screenshot rather than a description.

**Non-Goals:**

- A pattern language for describing formats. Formats are Swift parsers over a
  small field-reading helper, and the tree they produce is the contract.
- Loading format descriptions from files, comparing two binaries, disassembly,
  a bookmarks sidebar, or colouring by a user's own rules.
- Auto-saving a byte document, ever.
- Editing a file the machine cannot map. The current viewer has the same
  ceiling and nobody has reached it.
- Letting Claude change bytes. It explains; the person edits.

## Decisions

### The edits are pieces over the mapping, not a copy of the file

`ByteDocument` holds the mapped original and a piece table: a list of
`(source, offset, length)` runs where `source` is the mapping or an append-only
buffer of bytes typed or pasted. Reading byte `n` is a binary search over the
pieces; overwriting is a split and a new piece; inserting and deleting are
splits without a copy of anything but the piece list. The document is exactly
as large as its edits, so a 1 GB file with one byte changed costs one small
buffer, and undo is the piece list before the edit.

Saving writes the pieces in order to a temporary file beside the original and
renames it into place, then re-maps. Through a temporary because the original
is mapped by this very process: writing over a mapping you are reading from is
how a save produces a file that is half the old bytes and half the new.

*Ruled out:* a `Data` copy of the file with edits applied in place — the
viewer's one virtue was not copying, and a 1 GB `Data` is a 1 GB resident
allocation on the first edit. *Ruled out:* `NSTextStorage`-style character
storage over hex text — the model would be four times the file's size and
every offset would need dividing by three.

### Overwrite is the mode; insert is a switch that is shown

A hex editor is opened to change a byte far more often than to add one, and an
insert that shifts a gigabyte of structure by one byte is almost always a
mistake. So typing overwrites; insert is turned on deliberately, is named in
the bar and in the status bar while it is on, and turns itself off when the
tab is left. In insert mode Delete removes; in overwrite mode it does nothing,
because there is no byte to "remove" without shifting what follows.

*Ruled out:* insert as the default because text editors do it — the file is
not text, and the shifted-by-one Mach-O is the bug this decision prevents.

### One statistics pass, shared, in the background, with a block size chosen from the file

`ByteStatistics` walks the file once, sequentially, and for each block records
a 256-bin histogram folded into Shannon entropy and four class counts (zero,
printable, control, high). The block size is chosen so the file yields at most
about four thousand blocks — sixteen bytes for a small file, a quarter of a
megabyte for a gigabyte — so the pass is one sequential read and the result is
a few hundred kilobytes whatever the file. The minimap, the entropy curve and
the "likely compressed or encrypted" note all read the same result; nothing is
computed twice and nothing is computed on the main thread.

It runs on a task the document owns, cancelled when the tab closes, and the
views draw what has arrived so far: a gigabyte's minimap fills from the top
over a second or two rather than appearing after it.

An edit invalidates the blocks it touched, and only those.

*Ruled out:* per-byte colouring on the minimap — a strip two hundred pixels
tall cannot show a million rows, and computing it would be the whole file
again. *Ruled out:* computing on scroll — the minimap is the whole file by
definition, and a scroll-driven computation shows a strip that is mostly blank.

### Checksums are asked for, streamed, and marked stale rather than recomputed

Nothing hashes on open. Each algorithm is a button in the inspector; pressing
it streams the document's bytes — the pieces, so edits are included — through
CryptoKit (`SHA256`, `SHA512`, `Insecure.SHA1`, `Insecure.MD5`) or the
twenty-line CRC-32 and Adler-32, in a background task with a progress
indicator and a stop. The result is shown with a copy, and the moment a byte
changes it is greyed and labelled stale; it is not recomputed until asked,
since a SHA-256 of a gigabyte on every keystroke is a second of work per
nibble.

Over the selection when there is one, over the file otherwise, and the label
says which.

*Ruled out:* computing all six on open — six passes over a large file before
the person has asked a question. *Ruled out:* a dependency for CRC-32 — it is
a table and a loop.

### Search is a chunked scan with a first-byte skip, off the main thread

`ByteSearch` takes a pattern — a byte array with a wildcard mask, which is what
a hex pattern with `??`, a text query in an encoding, and a number in a width
and byte order all lower to — and scans the document in chunks of a few
megabytes, overlapping by the pattern's length so a match across a boundary is
found. Within a chunk it uses `memchr` for the first fixed byte and compares
the rest, which is what every fast grep does and is enough here.

It runs on a task the tab's `FindState` holds, reports matches as it goes so
the count climbs and the minimap fills, and is cancelled by a new query or the
bar closing. The find bar in byte mode shows how far through the file it is.

*Ruled out:* Boyer-Moore or two-way — the first-byte skip is within a small
factor on real binaries and is a tenth of the code. *Ruled out:* searching only
the visible region — a hex search is asked precisely to find what is *not* on
screen.

### Formats are Swift parsers producing one tree; the tree is the contract

`BinaryFormat` is a protocol: `static func recognises(_ head: Data) -> Bool`
and `func parse(_ reader: ByteReader) -> StructureNode`. `ByteReader` is a
small cursor over the document with typed reads in either byte order, and it
never throws past a bound: a read off the end produces a node that says
*truncated at 0x…* and parsing stops there, so a corrupt file yields the tree
up to the corruption and a sentence rather than nothing.

`StructureNode` is `(name, range, value, meaning, children, source)`, where
`source` is `.parsed` or `.claude`. It is the one thing the outline, the byte
highlighting, the caret's "you are in `IHDR.width`" label and the Claude answer
all speak. Fourteen formats ship, each a file under `Hex/Formats/`, each with a
fixture-backed test; a ZIP under another extension — JAR, 3MF, DOCX — is
recognised by its magic and named by its extension.

*Ruled out:* Kaitai Struct — its `.ksy` files need either a compiled parser
per format or an interpreter for the whole language, and the runtime is a
dependency; both are more than fourteen parsers. *Ruled out:* the ImHex
pattern language, for the same reason plus a language implementation.
*Ruled out:* a declarative YAML of our own — it would grow the expressions of
a language one format at a time, and the first format needing a conditional
would make it one.

### Claude is asked through `claude -p` with a bounded sample, and answers into the tree

`HexAnalysis` follows `ClaudeDraft` line for line where it can: the same
executable search, the same stdin prompt, the same *absent without the
command*, the same background run. What it sends is bounded by construction —
the first four kilobytes and the last one as a hex dump with offsets, the
selection up to eight kilobytes when the ask is about a selection, the
statistics pass's summary (size, entropy by region, the note), the strings
found, and the built-in tree when there is one, so Claude extends the parsed
structure rather than re-deriving it. It never sends the file.

It asks for two things: a paragraph, and a list of `{name, offset, length,
meaning}` rows. The rows become `StructureNode`s with `source: .claude`, drawn
in the outline under a heading that says so and in a different weight, and a
row whose range falls outside the file is dropped rather than drawn. What was
sent can be seen — a *Show what was asked* on the result — because an answer
about a sample should be judged knowing what the sample was.

The ask does not block: the outline says it is out, the editor stays editable,
and a second ask cancels the first. A failure is the command's own words, as
the commit draft's is.

*Ruled out for now:* handing Claude the `MCPServer` with `read_bytes` and
`find` tools so it can read what it wants of a large file. It is the better
design for a file whose structure is not in its head — a ZIP's central
directory is at the end, and a sample of the head and tail may miss it — but
it is a session that decides its own reading and its own running time, and
the draft path is the one this app has proven. It stays an open question below
rather than a rejection.

### The inspector pane lives in the tab, not in the sidebar

The data inspector follows the caret at keystroke frequency, and the structure
outline highlights bytes in the very view beside it; both belong in the tab,
in a split the way `PreviewSplitView` puts a rendered half beside a source
half. It collapses to nothing and remembers that.

*Ruled out:* feeding the sidebar's `StructurePane` — it is per window, follows
the active tab, and is a list of declarations from tree-sitter; a hex tab's
structure switching it into another vocabulary every time the tab changed
would be two panes fighting over one place.

### The tab carries a byte document beside its text one

`Tab` gains `bytes: ByteDocument?`; `isDirty` asks whichever exists; `save()`
dispatches; the close prompt and the edited dot fall out of `isDirty` as they
do today. `autoSaveIfNeeded` returns false for a byte document by construction.

*Ruled out:* a protocol both documents adopt — `TextDocument` is asked
questions about lines, languages and encodings that have no byte-document
answer, and a protocol thin enough to fit both would be `isDirty` and `save`,
which two optionals express without a type.

### The doors

The binary notice keeps its button — that is the door for a file the app
would not open as text anyway, and the notice's size line exists so the
person decides before a gigabyte is dumped. Two more: *Open as Hex* in the
tab's context menu and the palette for any file, and *Open as Text* on a hex
tab over a file the binary test passes. Neither is remembered per file or per
extension; the question is asked each time, which is the current behaviour
and has not been complained of.

### The driver

`--hex <steps>` in the shape of `--branch-rows`: comma-separated steps —
`goto:0x40`, `select:16`, `find:504B??04`, `type:FF`, `insert`, `inspect`,
`checksum:sha256`, `structure`, `entropy`, `ask`, `save` — and a report that
says what the status bar, the inspector and the outline say. `ask` is driven
against a fake `claude` on the `PATH` under the scratchpad, never the real one,
because a proof that costs a model call is not a proof that can be re-run.

## Risks / Trade-offs

- [A save over a file another process has open] → the rename is atomic and the
  other process keeps its old inode; that is the same behaviour as every
  editor's atomic save and is documented on the save.
- [An edit while the statistics pass is running] → the pass is per block and
  the edit invalidates blocks by range; a block finished before the edit and
  touched by it is recomputed, and a block not yet reached reads the document
  as it is when reached.
- [A hex pattern typed halfway — `50 4` — searched as typed] → the bar parses
  whole bytes only and shows the parse's complaint in place of a count, as the
  regex mode shows an invalid pattern.
- [Claude confidently naming fields that are not there] → every row it
  contributes is drawn as Claude's, out-of-range rows are dropped, and the
  prompt itself says to give offsets only where the bytes shown support them;
  the *Show what was asked* is there for the doubt that remains.
- [`EditorViewController.swift` growing] → nothing of the editor goes in it
  but the tab fields, the dispatches and the three doors; the allowance file
  is raised by what that measures and no more.
- [A test suite that maps large fixtures] → fixtures are generated in the test
  under the scratchpad at the size the claim needs, and the timing claims go
  through `Stopwatch.maySay` and print `MachineLoad.said`, as the house rule
  requires.
- [The structure tree over a 200 000-entry ZIP] → parsers cap repeated
  sections at a written count and produce a node that says how many were not
  listed; the outline is an `NSOutlineView` and is virtual regardless.

## Open Questions

- **Claude with tools.** Whether a second ask — *Investigate* — should hand
  Claude the loopback `MCPServer` with `read_bytes(offset, length)` and
  `find(pattern)`, so it can read a central directory at the end of a file or
  follow a pointer. The sample ask ships first; this is decided after it has
  been used.
- **Format descriptions as data.** Whether people should be able to drop a
  description file into the project for a format of their own. The tree is
  designed so that a loader producing `StructureNode`s would slot in; whether
  to write the loader is not decided here.
- **Bytes per row.** Sixteen, with eight and thirty-two as choices in the bar,
  or fitted to the width. The bar offers the three; whether *fit* is a fourth
  is left to the first screenshot.
