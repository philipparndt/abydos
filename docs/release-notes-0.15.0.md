# Abydos 0.15.0

## The hex viewer becomes an editor

The button had said *Open in Hex Editor* over a dump that could not select a
byte. Now it opens one.

- **A caret and a selection**, in the hex column and the text column, from
  the pointer and the keyboard; the status bar says the offset and the
  selection's length.
- **Find bytes**: a hex pattern with `??` wildcards, text in an encoding, or
  a number in a width and byte order. A gigabyte is searched in chunks behind
  the editor, with the count climbing and the matches ticked on the minimap.
- **Edit and save.** Typing overwrites; *Insert* is a switch the bar shows
  while it is on, and only then does Delete remove. Edited bytes are marked
  until ⌘S, which writes through a temporary and a rename. A byte document
  is never auto-saved.
- **Copy as hex, text, a C array or base64**; paste hex text or raw bytes.
  ⌘L goes to an offset, hex or decimal, absolute or relative.
- **An inspector beside the bytes**: integers of every width in either byte
  order, floats, a character, Unix times, LEB128, binary — and a value typed
  into a field is written back as bytes.
- **Checksums** on demand — CRC-32, Adler-32, MD5, SHA-1, SHA-256, SHA-512 —
  over the file or the selection, streamed, and marked stale when a byte
  changes.
- **Entropy** per block as a curve that reads its value under the pointer
  and takes a click or a sideways wheel to that part of the file, with
  regions above 7.5 bits named as likely compressed or encrypted; **a minimap** of the whole file coloured by
  what its bytes are or how random they are.
- **Known formats explained** as a tree of fields that selects bytes: PNG,
  JPEG, GIF, BMP, ZIP and what is a ZIP under another name, gzip, tar, ELF,
  Mach-O including fat binaries, PE, SQLite, RIFF/WAV, Java class and
  WebAssembly. A truncated file gets the tree up to the break and a node that
  says where.
- **Ask Claude** what a file or a selection is. A bounded sample goes to the
  `claude` command — never the file, never the API — and the answer comes
  back as rows in the same tree, drawn as Claude's and never as parsed fact,
  with the prompt one click away. Absent when there is no `claude`.
- **Strings**, listed and filtered, each a jump.
- **A hex tab is remembered** across a restart: that it was one, its caret,
  how it read the bytes, and what Claude said.
- **Any file can be opened as hex** from the project tree's context menu,
  the tab's menu, File ▸ Open as Hex and the palette; a hex tab over a text
  file goes back with Open as Text.
