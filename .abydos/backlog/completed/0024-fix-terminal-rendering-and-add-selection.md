# Fix terminal rendering and add selection

`c54d339d4` · 2026-07-31

Text can now be selected with the mouse and copied. Selections are held
in absolute rows so they survive scrolling, double-click takes a word —
including the dots and slashes that make it a path, which is what you
usually double-click in a terminal — and triple-click takes a line.
Copy takes the selection only; copying the whole buffer when nothing is
selected is a surprise nobody wants pasted somewhere else.

Three rendering and parsing faults, all reported:

- The cursor drifted away from the text. Cell width is rounded to whole
  points so run backgrounds abut exactly, but a run was drawn as one
  string and laid out by the font's fractional advance — about a fifth
  of a pixel per character, reaching a full cell by the time a prompt
  and a command have been typed. Text is now pinned to the grid.

- Claude Code came out entirely underlined and dimmed. It sends
  `CSI > 4 ; 2 m` (XTMODKEYS) on startup; the `>` was stripped and the
  rest read as SGR "underline, dim". Private-prefixed sequences share
  final bytes with standard ones and are not variants of them.

- Tab titles were mojibake: OSC strings were decoded a byte at a time,
  so the emoji in Claude Code's title arrived as three Latin-1
  characters. They are UTF-8.

Also: SGR `4:0` means *no* underline, not underline with a decoration.
