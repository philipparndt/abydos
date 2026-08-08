# 407. Ligatures in a tmux pane depend on which pane is active

Two screenshots of the same `brew upgrade` output in the same pane, one while
the pane held the cursor and one while it did not, disagree about which
operators join:

| Text            | Inactive          | Active            |
| --------------- | ----------------- | ----------------- |
| `==>`           | joined, one arrow | three characters  |
| `2.1.224 -> 2.1.226` | two characters | joined, one arrow |

And it goes the other way too: a later report has the focused pane as the one
*with* ligatures and the unfocused one without. So this is not "ligatures are
off for the active pane" in either direction — each state joins something the
other does not, and which is which is not stable. Which is the useful part of the report — it rules
out the setting, the font, and the shaper being asked at all, and points at
*what the shaper is being given*.

**Where to look.** A run is the unit shaped, and a run ends where the cell
attributes change:

    while end < cells.count, cells[end].attributes == cells[start].attributes { end += 1 }

in `TerminalMetalRenderer.ligatures(in:faces:)`, and the same rule on the other
path in `TerminalView.drawRun`. `Ligatures.mayLigate` then needs two operator
characters *inside one run*, so an `==>` whose first `=` carries a different
attribute from the rest is three characters by construction, and nothing
downstream can join it. That fits an active pane differing from an inactive one:
what changes with focus is not the drawing but what the emulator was told, and
`==>` in brew's output is coloured while the version arrow is not.

Also worth ruling in or out, in this order:

- Whether both panes are even on the same path. `updateMetalEnabled()` is per
  view and `terminalGPURendering` is global, so a view that existed before the
  switch was flipped keeps the path it was created with — and the two paths
  shape separately, one through `ShapedRuns` with a cache and one through
  `CTLine` with none.
- `drawLigated` gives up on a whole run — `return false`, per-cell path, no
  ligatures — for any run holding a powerline separator, a box-drawing
  character, or a picture placeholder. Both screenshots have a powerline prompt
  and a pane border in them.

**How to get the evidence.** e42eb08 added recording of what the terminal was
actually given. Capture the same line with the pane active and inactive, and
diff the attributes per cell: if they differ, the answer is above and the fix is
about run splitting rather than about shaping. Recording the runs `mayLigate` is
asked about would say it outright.

---

Its number is where it sits in the queue, not what it is worth doing next.
Previously numbered 396.
