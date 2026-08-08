# 407. Ligatures in a tmux pane depend on which pane is active

**It was the pane border, and it was the second candidate on the list below
rather than the first.** The run boundaries were right all along; what was
wrong is what a run did when it met a character the terminal draws itself.

tmux paints the border of the pane that is *not* active with
`pane-border-style`, and that option is `default` out of the box — the same
attributes as ordinary text. So the border column lands in the *same* run as
the text either side of it. The border is a box drawing, and a run holding one
gave up whole: `usable = false` in `ligatures(in:faces:)`, `return false` in
`drawLigated`. Every line the border crossed lost its ligatures. Making the
other pane active paints that border green, which ends the run before it, and
they all came back.

`tmux show -gw window-style window-active-style` printing nothing was true and
was the wrong option to look at: a border is not a window style, and
`pane-active-border-style` is `fg=green` on a stock tmux.

The evidence, recorded before anything was changed, from a real tmux 3.7
attach on 80x24 with one vertical split, the same three rows replayed through
the emulator with each pane active in turn:

    === left pane active (border green: fg=i2) ===
    row 1 run 0..<40 fg=def bg=def
      text "node 2.1.224 -> 2.1.226                 "
      cellOfOffset [0, 1, 2, … 39]
      pieces 40, carriers (no ink) at columns [4, 12, 13, 15, 23 …]
                                                      ^^ the `-` of `->` joins

    === right pane active (border default: fg=def) ===
    row 1 run 0..<80
      REFUSED: tiles U+2502 at column 40 — the whole run draws per cell

Same bytes, same row, same font, same setting. The only difference between the
two is which pane tmux thinks is active, and it moves the *run boundary*, not
the shaping. The blue `==>` above it is `fg=i4`, a run of three cells that
never touches the border, and it joins in both — which is the report's "only
some positions" exactly.

The fix is the opposite of the one that was reverted: a span **stops** at a
character that cannot be shaped instead of the run giving up on it.
`Ligatures.spans(in:canShape:)` cuts a run into the stretches a font can be
asked about, and both paths shape those. Runs holding nothing of the sort —
which is nearly all of them, and every plain `==>` — are shaped exactly as
before, so this can only ever add ligatures, never take one away. That is the
difference from the widening attempt, which changed what a *good* run was
given and inverted which operators joined.

Two things fall out of it that also match the report: the same is true of a
powerline separator in a prompt and of a picture's placeholder, which is why
the prompt line in the screenshots behaved the same way; and it survives a
restart because it is decided by what is in the cells, which tmux replays the
same way every time.

Photographed before and after in a real tmux split, on both renderers: with
the right pane active the unfixed build draws `-> != |>` plainly and the fixed
one draws them joined, while the left pane active joins them either way.

Below, what was known while it was being looked for.

---

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

**What the two screenshots of the same pane show** is a repaint, not shaping:
`==> Done:` and `==> Installed` sit there unligated, and the moment focus
enters the window both of them join — the same rows, the same text, no output
in between. Whatever a row was painted with, it keeps.

**But it survives a restart**, which kills the two easy explanations. Stale
pixels do not outlive the process, and neither does a stale font — every view
builds its own from `Theme.terminalFont`, which reads the switch at the moment
it is built. Whatever this is, it is decided again on every launch and comes
out the same way, per pane.

Ruled out on the machine it happens on: tmux is not styling its panes
differently. `tmux show -gw window-style window-active-style` prints nothing,
so the active and inactive panes are not being sent different attributes by
tmux's own configuration — which was the obvious candidate, since a run ends
where the cell attributes change and a dimmed pane would end every run.

That leaves what the *program in the pane* is sending, which differs with
focus for a reason of its own: mode 1004. tmux passes focus in and focus out
through to whatever is running there, and a full-screen program told it has
lost focus commonly redraws itself more plainly — fewer colours, no bold. If
that is what is happening, the ligatures are following the attributes of the
redraw rather than the focus, and the pane that "only ligates unfocused" is the
one whose program draws *fewer* attribute changes in that state.

**And it is not the whole pane — only some positions in it.** Within one pane,
with one setting and one font, some operators join and others do not. That
rules out everything global and leaves one thing: a ligature is shaped inside
a *run*, and a run ends where the cell attributes change.

    while end < cells.count, cells[end].attributes == cells[start].attributes { end += 1 }

An operator with a colour change in the middle of it is two runs of one
character each, `mayLigate` says no to both, and it draws plainly — while the
identical operator a few columns along, inside one run, joins. Which is
position-dependent, per pane, survives a restart, and moves when the program
repaints itself with different attributes on focus. All four of the things
this bug does.

If that is it, the fix is not in the ligature code but in what it is given:
shape the line's text and apply the colours per cell afterwards, rather than
shaping each colour separately. A ligature is a property of the characters and
a colour is a property of the cell, and today the second decides the first.

**That was tried and reverted — read this before trying it again.** Runs were
widened to every neighbouring cell sharing a *face* (bold, italic, hidden),
with each run painting only its own cells of the shared shaping. It worked on
the case it was written for: `==>` split red/green mid-operator joined, and so
did `!!` split across colours. And it broke the ordinary case — a plain `==>`
with no boundary in it stopped joining, on both renderers, while the split one
still did. So widening the run inverted which operators join rather than fixing
which, and whatever is wrong is in how the widened span maps back to cells, not
in the idea.

Two things were learned on the way and are worth keeping:

- Widening the span makes the bail-outs far more expensive than they look.
  `drawLigated` returns false for a whole span holding a powerline separator, a
  box drawing or a placeholder, and a wide span in a prompt or beside a pane
  border always holds one — so ligatures vanish from the line entirely.
  Stopping the span at those cells rather than failing on them is necessary but
  was not sufficient.
- The Metal path and the CG path agreed exactly, before and after, which says
  the fault is in the shared idea rather than in either renderer.

Next time: get the evidence first. Record the span text, the `cellOfOffset` it
is given and the pieces that come back for a plain `==>` and for a split one,
and find out why the plain one produces no join, before changing how runs are
built.

Checkable without guessing: e42eb08 records what the terminal was given.
Capture a line where one operator joins and another does not, and compare the
attributes either side of each.

**One more pair, and a caveat about it.** Unfocused, the build output above the
prompt reads `==> Done:` and `==> Installed` plainly while the prompt line
typed a moment ago joins its `==>`; focused, all of them join. Older rows
plain, newest row joined, is the signature of the CG path, which repaints only
the rows that changed — so the pane to suspect is one where `metal == nil`,
and `updateMetalEnabled()` is per view: a view made before the GPU switch was
flipped keeps the path it was made with.

The caveat is in the screenshot itself, three lines up: *"a copy is still
running the previous build — quit and reopen it to get this one"*. Both shots
are of the binary from before the carrier fix, so whatever they show has to be
confirmed against a build that has it.

Below, the earlier reasoning, which still applies to the repaint half:

    setNeedsDisplay(rect(forAbsoluteRows: range))

so a row painted while ligatures were off stays that way for as long as
nothing touches it, and taking focus repaints the view whole. The Metal path
redraws everything every frame and cannot show this. So the first thing to
find out is whether the panes that differ are the ones on different renderers
— `updateMetalEnabled()` is per view, and `terminalGPURendering` is global but
only applied when a view is made or the setting changes.

`applyThemeChange()` is the existing "start again" hook: it clears the glyph
atlas *and* the shaped-run cache and repaints in full. If the answer is that
a setting change has to reach every pane, that is the thing to call, and
`BottomPanel.applySettings` already calls it for terminal panes — worth
checking whether the ligature switch goes through there at all.

Separately: the doubling this was confused with — one dot too many for `..`,
the first of `!!` painted twice — was a different bug in the Metal path and
is fixed. This entry is only about ligatures appearing and disappearing.

**Where to look next.** A run is the unit shaped, and a run ends where the cell
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
