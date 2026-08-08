# Make the whole UI zoomable with ⌘+ / ⌘- / ⌘0

`ff3922da8` · 2026-07-30

Adds a single uiScale setting that every dimension in the window derives from,
via Theme.scaled(_:) and Theme.uiFont(_:). Zooming moves the interface as one
piece — tree rows, indentation, icons, tab strip, gutter, editor text, status
bar, tool strip and titlebar pills — rather than growing text while its
surroundings stay put.

Zoom uses discrete steps so repeated presses land on predictable values and ⌘0
returns to exactly 1.0. The Settings slider is continuous for fine adjustment.

Icon cache is keyed by scale as well as symbol, otherwise zooming served stale
low-resolution glyphs.

57 tests.
