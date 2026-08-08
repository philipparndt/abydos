# Keep terminal content when the pane is resized

`92f3c2d78` · 2026-07-31

Three separate faults, all visible as lines vanishing or output being
printed twice:

- Shrinking always retired rows off the top, even when the bottom of the
  screen was untouched. A short session pushed its own prompt and
  everything above it into scrollback. Blank rows below the cursor are
  now discarded first, and only then is real content retired.

- The cursor was clamped into the new bounds rather than moved with the
  content under it. Both retiring from the top and recovering scrollback
  on growth shift every row, so the shell's post-SIGWINCH redraw landed
  on the wrong line and duplicated the prompt. resize() now returns how
  far the grid moved and the emulator applies it.

- The saved normal screen was never resized, so resizing inside tmux and
  then leaving it restored a grid of the old shape.

The view had the same ordering fault: it decided whether it was following
output after changing the grid, comparing an old offset against a new
maximum. That unpinned a view that was tracking the prompt, which then
sat off screen behind stale lines.
