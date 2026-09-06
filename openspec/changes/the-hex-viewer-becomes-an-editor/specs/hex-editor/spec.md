## ADDED Requirements

### Requirement: A file looked at as bytes has a caret and a selection

The hex editor SHALL have a caret at a byte and a selection over a range of
bytes, set by the pointer — click, drag, shift-click — and by the keyboard —
the arrows, ⇧ with them, ⌥ by a word of eight, ⌘ to the ends of a row and of
the file, ⌘A for everything. The caret and the selection SHALL be drawn in
both the hex column and the text column, with the column that has the
keyboard drawn as the active one. The status bar SHALL say the caret's offset
in hex and decimal and, when there is a selection, its start, end and length.

The button has said *Open in Hex Editor* since the notice gained its size
line, over a view that could not select a byte; an editor begins with a caret.

#### Scenario: a drag in the hex column

- **GIVEN** a file open as bytes
- **WHEN** the pointer drags from the byte at 0x10 to the byte at 0x1F
- **THEN** sixteen bytes are selected in both columns, and the status bar says
  0x10 to 0x1F, sixteen bytes

#### Scenario: ⇧→ from a caret

- **GIVEN** the caret on byte 0x20 and nothing selected
- **WHEN** ⇧→ is pressed three times
- **THEN** bytes 0x20 to 0x22 are selected

#### Scenario: the keyboard is in the text column

- **GIVEN** the text column clicked
- **THEN** its caret is drawn as the active one, the hex column mirrors it,
  and typing goes to the text column

### Requirement: Bytes can be searched, and a large file stays responsive while they are

The find bar SHALL have a byte mode for a hex tab with three kinds of query: a
hex pattern in which `??` matches any byte, text in a chosen encoding among
ASCII, UTF-8 and UTF-16 little- and big-endian, and a number in a chosen width
among 8, 16, 32 and 64 bits and a chosen byte order. Matches SHALL be
highlighted in both columns, counted in the bar, stepped through with the
bar's next and previous, and ticked on the minimap.

The search SHALL run off the main thread in chunks, reporting matches as it
finds them so the count climbs, SHALL say how far through the file it is, and
SHALL be cancelled by a new query or the bar closing. A hex pattern that is not
whole bytes SHALL show the parse's complaint in place of a count rather than
search half a byte.

#### Scenario: a hex pattern with a wildcard

- **GIVEN** a ZIP file
- **WHEN** `50 4B ?? 04` is searched
- **THEN** every local file header and every data descriptor whose third byte
  differs is a match, counted and highlighted

#### Scenario: a number in a byte order

- **GIVEN** a file holding the 32-bit little-endian value 1000 at 0x40
- **WHEN** `1000` is searched as a 32-bit little-endian number
- **THEN** 0x40 is a match, and searching it big-endian is not

#### Scenario: a gigabyte while typing

- **GIVEN** a 1 GB file open as bytes
- **WHEN** a pattern is typed
- **THEN** the editor scrolls and selects while the count climbs, the bar
  says what fraction has been searched, and typing another character stops
  the first search

#### Scenario: half a byte

- **GIVEN** `50 4` typed
- **THEN** the bar says the pattern is not whole bytes and nothing is searched

### Requirement: Bytes can be edited, and overwrite is the mode

Typing a hex digit at the caret in the hex column SHALL replace the high
nibble then the low nibble of the byte there and advance; typing a character
in the text column SHALL replace the byte with its encoding. Overwrite SHALL be
the default. Insert SHALL be a mode turned on deliberately, named in the bar
and in the status bar while it is on, and turned off when the tab is left. In
insert mode typing SHALL insert before the caret and Delete SHALL remove; in
overwrite mode Delete SHALL do nothing.

Edited bytes SHALL be marked until they are saved. Every edit SHALL be undone
and redone with ⌘Z and ⇧⌘Z through the window's undo manager.

An insert that shifts a gigabyte of structure by one byte is almost always a
mistake, and a mode that is on without being named is how it happens.

#### Scenario: typing over a byte

- **GIVEN** the caret on a byte reading 00 in overwrite mode
- **WHEN** `F` then `F` is typed
- **THEN** the byte reads FF, is marked edited, and the caret is on the next byte

#### Scenario: Delete in overwrite mode

- **GIVEN** overwrite mode and a caret
- **WHEN** Delete is pressed
- **THEN** nothing changes

#### Scenario: insert, named

- **GIVEN** insert mode turned on
- **THEN** the bar and the status bar both say *Insert*
- **WHEN** `41` is typed
- **THEN** a byte 41 is inserted before the caret and every byte after it is
  one further on

#### Scenario: undoing an overwrite

- **GIVEN** a byte overwritten
- **WHEN** ⌘Z is pressed
- **THEN** the byte reads what it did, and the edited mark is gone

### Requirement: A byte document is saved on ⌘S through a temporary, and never on its own

⌘S on an edited hex tab SHALL write the document to a temporary file beside
the original and rename it into place, then map the new file. A byte document
SHALL NOT be auto-saved, whatever the auto-save setting says. The tab SHALL
show the edited dot while there are unsaved edits, and closing it SHALL ask,
as a text tab does.

Through a temporary because the original is mapped by this very process, and
writing over a mapping you are reading from yields a file that is half old
bytes and half new. Never auto-saved because half a typed nibble written into
a Mach-O is a corrupted binary, not a draft.

#### Scenario: save and reopen

- **GIVEN** three bytes overwritten and ⌘S pressed
- **WHEN** the file is opened again
- **THEN** it holds the three new bytes and is otherwise byte-for-byte the
  file it was, and the edited marks are gone

#### Scenario: auto-save on, hex tab edited

- **GIVEN** auto-save on and a byte overwritten
- **WHEN** the auto-save interval passes and the window loses focus
- **THEN** the file on disk is unchanged and the tab still shows the dot

#### Scenario: closing an edited hex tab

- **GIVEN** an unsaved edit
- **WHEN** the tab is closed
- **THEN** it asks, as a text tab with an unsaved edit asks

### Requirement: The selection is copied in the shape asked for, and pasted as bytes

The hex tab SHALL copy the selection as hex (`50 4B 03 04`), as text in the
text column's encoding with unprintables as dots, as a C array
(`{ 0x50, 0x4B, ... }`) and as base64, from the edit menu and the context
menu, with plain ⌘C copying hex when the hex column is active and text when
the text column is. Paste SHALL accept hex text — whitespace, `0x` prefixes and
commas ignored — and raw bytes, and SHALL overwrite or insert according to the
mode.

#### Scenario: copy as C array

- **GIVEN** four bytes selected
- **WHEN** *Copy as C Array* is chosen
- **THEN** the pasteboard holds `{ 0x50, 0x4B, 0x03, 0x04 }`

#### Scenario: paste hex text

- **GIVEN** `de ad, 0xBE 0xEF` on the pasteboard and overwrite mode
- **WHEN** ⌘V is pressed
- **THEN** four bytes from the caret read DE AD BE EF

### Requirement: The caret goes to an offset asked for in hex or decimal

⌘L on a hex tab SHALL ask for an offset and put the caret there. The field
SHALL take hex with or without `0x`, decimal, and a relative offset with a
leading `+` or `-` from the caret, and SHALL say when the offset is past the
end rather than clamping silently.

#### Scenario: hex and decimal

- **GIVEN** the field open
- **WHEN** `0x1000` is entered
- **THEN** the caret is at 4096, and entering `4096` puts it in the same place

#### Scenario: relative

- **GIVEN** the caret at 0x100
- **WHEN** `+0x20` is entered
- **THEN** the caret is at 0x120

#### Scenario: past the end

- **GIVEN** a 100-byte file
- **WHEN** `200` is entered
- **THEN** the field says the file is 100 bytes long and the caret stays

### Requirement: The inspector says what the bytes at the caret are, and takes a value back

An inspector beside the bytes SHALL show, for the bytes from the caret: signed
and unsigned integers of 8, 16, 32 and 64 bits, 32- and 64-bit floats, a
character in the text column's encoding, a Unix time in 32 and 64 bits, an
unsigned LEB128, and the byte in binary — each in the byte order the inspector
is set to, which SHALL be a switch. A value near the end of the file that
needs more bytes than remain SHALL be shown as unavailable rather than read
past the end.

Each integer and float SHALL be editable: a value typed into it SHALL be
written as bytes at the caret in the chosen order, through the same edit path
as typing, so it is marked and undone the same way.

#### Scenario: a 32-bit integer both ways

- **GIVEN** the caret on the bytes 01 00 00 00
- **THEN** the 32-bit unsigned reads 1 little-endian and 16777216 big-endian

#### Scenario: a time

- **GIVEN** the caret on the little-endian 32-bit value 1 700 000 000
- **THEN** the Unix time reads 2023-11-14 22:13:20 UTC

#### Scenario: typing a value

- **GIVEN** the caret on four zero bytes, little-endian selected
- **WHEN** 258 is typed into the 16-bit unsigned field
- **THEN** the bytes read 02 01 00 00, the first two marked edited

#### Scenario: at the end

- **GIVEN** the caret on the last byte
- **THEN** the 8-bit values are shown and every wider one says it needs more
  bytes than there are

### Requirement: Checksums are computed when asked, streamed, and marked stale

The inspector SHALL offer CRC-32, Adler-32, MD5, SHA-1, SHA-256 and SHA-512,
each computed only when its button is pressed, over the selection when there
is one and the whole document otherwise, with the label saying which. Each
SHALL stream the document's bytes — edits included — without reading the file
into memory, off the main thread, with progress and a stop. The result SHALL have a copy. The moment a byte changes, every shown result over bytes the
change touched SHALL be greyed and labelled stale, and SHALL NOT be recomputed
until asked again; a digest over a selection the change did not touch stands.

A SHA-256 of a gigabyte on every keystroke is a second of work per nibble.

#### Scenario: the empty file's known digest

- **GIVEN** an empty file
- **WHEN** SHA-256 is asked for
- **THEN** it reads e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

#### Scenario: over the selection

- **GIVEN** bytes 0x10 to 0x1F selected
- **WHEN** CRC-32 is asked for
- **THEN** the result is the CRC-32 of those sixteen bytes and the label says
  *selection, 16 bytes*

#### Scenario: an edit after a result

- **GIVEN** a SHA-1 of the whole file shown
- **WHEN** a byte is overwritten
- **THEN** the SHA-1 is greyed and says stale, and is not recomputed until
  pressed again

#### Scenario: an edit outside a selection's digest

- **GIVEN** a CRC-32 of bytes 0x20 to 0x2F shown
- **WHEN** the byte at 0x100 is overwritten
- **THEN** the CRC-32 still stands

#### Scenario: a gigabyte

- **GIVEN** a 1 GB file
- **WHEN** SHA-512 is asked for
- **THEN** the editor stays usable, progress climbs, and stop ends it

### Requirement: Entropy is computed once per block, drawn as a curve, and named where it is high

The document SHALL compute Shannon entropy per block in one background pass
over the file, with the block size chosen so the file yields at most about
four thousand blocks. The inspector SHALL draw the result as a curve from zero
to eight bits a byte with the viewport marked on it, filling as the pass
arrives rather than after it. A run of blocks above 7.5 bits SHALL be named
in words as likely compressed or encrypted, with its offset range, and
choosing it SHALL select those bytes. An edit SHALL invalidate the blocks it
touched and only those.

#### Scenario: a file with a compressed tail

- **GIVEN** a file whose first half is a text header and second half is a
  gzip stream
- **THEN** the curve is low then near eight, and one note names the second
  half's range as likely compressed or encrypted

#### Scenario: the pass on a gigabyte

- **GIVEN** a 1 GB file
- **WHEN** it is opened
- **THEN** the editor is usable at once, and the curve fills from the left
  within a few seconds without the editor stalling

#### Scenario: an edit

- **GIVEN** the pass finished
- **WHEN** one byte is overwritten
- **THEN** one block is recomputed and the rest are not

### Requirement: A minimap shows the whole file, and moves the view

A strip at the editor's right edge SHALL show the whole file, each row of
pixels one block, coloured by the block's mix of zero, printable, control and
high bytes or — on a switch — by its entropy, from the same pass as the curve.
It SHALL draw the viewport as a rectangle, the search matches and the edited
ranges as ticks, SHALL scroll the editor to where it is clicked or dragged,
and SHALL be drawn from a cached picture that is remade only when the pass
delivers or the window resizes, never per scroll.

#### Scenario: an ELF binary

- **GIVEN** an ELF binary open
- **THEN** the strip shows its sections as bands — headers, code, strings,
  zeros — and the viewport rectangle is at the top

#### Scenario: click to move

- **GIVEN** the viewport at the top
- **WHEN** the strip is clicked two thirds of the way down
- **THEN** the editor scrolls to two thirds of the way through the file

#### Scenario: matches on the strip

- **GIVEN** a search with matches
- **THEN** each match is a tick on the strip at its offset

### Requirement: A known format is explained as a tree of its fields

A file whose magic a built-in parser recognises SHALL show, in the inspector,
a tree of fields — name, offset, length, value and meaning — that selects the
field's bytes when a row is chosen and names the field the caret is in above
the bytes. The built-in formats SHALL be PNG, JPEG, GIF, BMP, ZIP, gzip, tar,
ELF, Mach-O including fat binaries, PE, SQLite, RIFF and WAV, Java class and
WebAssembly, with a ZIP under another extension — JAR, 3MF, DOCX — recognised
by its magic and named by its extension. A truncated or malformed file SHALL
yield the tree up to where parsing stopped and a node saying where and why.
A repeated section SHALL be capped at a written count with a node saying how
many were not listed.

#### Scenario: a PNG

- **GIVEN** a PNG
- **THEN** the tree has the signature, then a chunk per chunk — IHDR with
  width, height, bit depth and colour type as named values, IDAT with its
  length, IEND — and choosing IHDR's width selects its four bytes

#### Scenario: the caret's field

- **GIVEN** the caret on byte 0x14 of a PNG
- **THEN** the label above the bytes reads *IHDR › height*

#### Scenario: a JAR

- **GIVEN** a `.jar`
- **THEN** it is explained as a ZIP and the tree's root says *JAR (ZIP)*

#### Scenario: a truncated ZIP

- **GIVEN** a ZIP cut off in its third local header
- **THEN** the tree has two entries and a node reading *truncated at 0x… in
  local file header 3*

#### Scenario: a file nobody recognises

- **GIVEN** a file whose magic matches no parser
- **THEN** the tree says no built-in format recognised it and offers the ask
  to Claude

### Requirement: Claude can be asked what a file or a selection is, and answers into the tree

The inspector SHALL offer *Ask Claude* about the file and, when there is a
selection, about the selection. The ask SHALL go through the `claude` command
on the `PATH` or in the per-user places the commit draft looks, with the
prompt on stdin, and SHALL be absent when there is no command. It SHALL send a
bounded sample and never the file: the first four kilobytes and the last one
as a hex dump with offsets, the selection up to eight kilobytes when the ask is
about one, the entropy summary and note, the strings found, and the built-in
tree when there is one. It SHALL ask for a paragraph and a list of rows with
name, offset, length and meaning; the rows SHALL become nodes drawn under a
heading naming Claude as their source and in a different weight from parsed
nodes, and a row whose range is outside the file SHALL be dropped. What was
sent SHALL be viewable from the result. The ask SHALL NOT block editing, a
second ask SHALL cancel the first, a failure SHALL be shown in the command's
own words, and nothing Claude says SHALL change a byte.

#### Scenario: an unknown file

- **GIVEN** a file no parser recognises and `claude` installed
- **WHEN** *Ask Claude* is pressed
- **THEN** the outline says the ask is out, the editor still edits, and the
  answer arrives as a paragraph and rows headed *Claude says*

#### Scenario: no command

- **GIVEN** no `claude` anywhere it is looked for
- **THEN** the button is not there

#### Scenario: a row past the end

- **GIVEN** an answer with a row at an offset beyond the file's length
- **THEN** that row is not drawn and the rest are

#### Scenario: what was asked

- **GIVEN** an answer shown
- **WHEN** *Show what was asked* is chosen
- **THEN** the prompt is shown, and its hex dump is no more than five
  kilobytes of the file

### Requirement: Printable strings are listed, each a jump

The inspector SHALL list runs of four or more printable bytes in the text
column's encoding, with their offsets, filtered by a field, and choosing one
SHALL select it in the editor. The list SHALL be built in the background and
capped at a written count with a row saying how many more there are.

#### Scenario: a binary with a usage string

- **GIVEN** a compiled program that prints *usage:*
- **WHEN** `usage` is typed into the filter
- **THEN** the row is listed with its offset, and choosing it selects the bytes

### Requirement: Any file can be opened as hex, and a text file can go back

The project tree's context menu, the tab's context menu, the File menu and
the palette SHALL offer *Open as Hex* for any file, including one open as
text, and a hex tab over a file that passes the binary test SHALL offer *Open
as Text*. The binary notice SHALL keep its *Open in Hex
Editor* button as the door for a binary. Neither choice SHALL be remembered per
file or per extension.

#### Scenario: a text file as bytes

- **GIVEN** a `.swift` file open as text
- **WHEN** *Open as Hex* is chosen
- **THEN** the same tab shows it as bytes, and *Open as Text* takes it back

#### Scenario: from the project tree

- **GIVEN** a `.png` in the tree
- **WHEN** *Open as Hex* is chosen from its context menu
- **THEN** it opens in a tab as bytes, not as the picture

#### Scenario: the notice's button

- **GIVEN** a `.bin` opened
- **THEN** the notice with its size line appears, and its button opens the
  hex editor in the same tab

### Requirement: A large file costs what the viewer costs today

Opening a file as bytes SHALL map it rather than read it, SHALL format only the
visible rows, and SHALL keep edits as pieces over the mapping so a one-byte
edit to a gigabyte costs bytes, not gigabytes. Every whole-file computation —
the statistics pass, a search, a checksum, the strings list — SHALL run off the
main thread and be cancellable. A 1 GB file SHALL open within the viewer's
current time and SHALL scroll at full speed while every one of those runs.
Timing claims SHALL be made through `Stopwatch.maySay` and printed with
`MachineLoad.said`.

#### Scenario: a gigabyte with one edit

- **GIVEN** a 1 GB file open as bytes
- **WHEN** one byte is overwritten
- **THEN** the process's resident memory grows by kilobytes, and ⌘S writes a
  gigabyte through the temporary and renames it

#### Scenario: everything at once

- **GIVEN** the statistics pass, a search and a SHA-256 all running on a
  gigabyte
- **THEN** scrolling and selecting are at full speed, and closing the tab
  stops all three

### Requirement: The hex editor follows the zoom

Every view of the hex editor — the bytes, the bar, the minimap, the inspector
and its rows, the structure outline — SHALL take its fonts, its heights and
its spacing from the theme and re-take them when the zoom or the palette
changes, through the same registry every scaled control uses. No part of it
SHALL take its size from an AppKit `controlSize`, which has a largest value
and walls out at roughly 1.4×.

#### Scenario: zooming with a hex tab open

- **GIVEN** a hex tab at 1.0×
- **WHEN** the zoom is set to 1.4×
- **THEN** the byte cells, the bar's fields and popups, the inspector's
  values and the outline's rows are all larger, and none of them stops
  growing before the rest

### Requirement: The hex editor is driven from the launch options

`--hex <steps>` SHALL take comma-separated steps — `goto:<offset>`,
`select:<count>`, `find:<pattern>`, `type:<hex>`, `insert`, `inspect`,
`checksum:<name>`, `structure`, `entropy`, `strings`, `ask`, `save` — perform
them in order on the hex tab, and print a report of what the status bar, the
inspector and the outline say after each. `ask` SHALL run against whatever
`claude` is on the run's `PATH`, so the proof uses a fake one under the
scratchpad and never a real model.

#### Scenario: a driven selection and inspection

- **GIVEN** `--open <copy> --file image.png --hex "goto:0x10,select:4,inspect"`
- **THEN** the report says the caret at 0x10, four bytes selected, the 32-bit
  big-endian value that is the PNG's width, and the field *IHDR › width*

#### Scenario: a driven ask

- **GIVEN** a fake `claude` first on the `PATH` that answers a fixed paragraph
  and two rows
- **WHEN** `--hex "ask"` runs
- **THEN** the report has the paragraph and the two rows under *Claude says*
