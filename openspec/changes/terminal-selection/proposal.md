## Why

Selecting in a terminal highlights the whole width of the grid, whatever the
text on the row actually is. Dragging over a two-word prompt lights up eighty
columns of nothing, and a selection across several lines is a solid rectangle of
highlight with the text somewhere inside it — so what is selected has to be
guessed at rather than seen. Every other terminal on this machine stops the
highlight at the end of the line.

The copied text is already right — `TerminalLine.text(in:)` trims trailing
blanks — which is why this has survived: the fault is entirely in what is shown,
and it is shown on every drag.

The second half is a gesture that is missing rather than wrong. Terminal output
is full of columns — `ls -l`, `ps`, `git log --oneline`, a table from a
migration — and taking one column out of it is not possible at all today.

## What Changes

- A selection's highlight stops at the end of each row's text instead of running
  to the right edge of the grid.
- A press or a drag past the end of a row lands at the end of that row's text
  rather than in the blank cells beyond it, so what is anchored and what is
  copied agree with what is drawn.
- **Option held while dragging selects a rectangle** — the same columns on every
  row it covers — and copying one joins the rows with newlines, each trimmed.
- A row inside a selection that has no text on it keeps a narrow mark, so a run
  of blank lines reads as part of the selection rather than as the end of it.
- Double-click, triple-click and Select All are unchanged; so is what a
  selection copies for the rows that have text on them.

## Capabilities

### New Capabilities
- `terminal-selection`: what a drag in a terminal selects, what it draws, and
  what it copies — including the rectangular selection Option makes.

### Modified Capabilities

None. `openspec/specs/terminal` describes engines, redraw, mouse forwarding and
pane lifetime; it says nothing about selection geometry, so this adds a
capability rather than changing one.

## Impact

- `TerminalSelection.swift` — the range a row contributes, and a `isBlock` flag
  on the selection itself.
- `TerminalScreen.swift` — `TerminalLine` gains the column its text ends at,
  which nothing has needed until now.
- `TerminalView.swift` — where a click becomes a position, where a drag updates
  one, and the highlight both renderers draw from.

Both engines are affected and neither is changed: the selection helpers live on
`TerminalGridReading`, which our emulator and libghostty-vt both conform to, so
there is one implementation to change rather than two.
