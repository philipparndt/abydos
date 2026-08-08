# 408. A glyph is painted twice where two operators meet

In `repository("!! app/build/\n")` the first `!` is drawn twice, a fraction of
a cell apart, so it reads as bold or smeared beside its neighbour. Reported
again a minute later in a terminal pane, on `container-apiserver...`, and that
one says more: what is on screen is an ellipsis glyph *and* a dot after it.

**Not a merge, measured.** The obvious explanation — the font turning three
characters into one glyph and the other two cells failing to be suppressed —
is wrong for the font this ships. Shaping `...`, `!!`, `->` and `==` with
`JetBrainsMonoNerdFontMono-Regular` returns one glyph per character every time,
each with the same 8.4pt advance:

    3 chars "..." -> glyphs=3 indices=[0, 1, 2] advances=[840, 840, 840]
    2 chars "!!" -> glyphs=2 indices=[0, 1] advances=[840, 840]

which is the property the code relies on and states. So the count is right and
something else about where a shaped glyph is *placed* is not. Two cells' worth
of ink in one cell, with the neighbour still drawing its own, is what an offset
by one cell would look like.

**Both places at once is the useful part.** One report is the editor's code
view and the other is a terminal pane, and they do not share a renderer — so
the fault is in the part they do share, which is the shaping. The switch
arrived recently in three commits (32b8a68, f2f15ae, 8e62819), and the third
of those was already a bug in how a shaped run is keyed.

**Leading candidate: a cell drawn by the shaper *and* by itself.** Both paths
work the same way — ask the font what joins, then put the pieces back on the
grid — and both mark the cells a ligature covers so that nothing else draws
them:

- `TerminalMetalRenderer.ligatures(in:faces:)` builds `[Int: Piece?]`, where
  `.some(nil)` means "swallowed"; the run is marked swallowed first and the
  pieces are written back afterwards, keyed by `start + piece.cellOffset`.
- `TerminalView.drawLigated` draws the run itself and returns true, and the
  per-cell loop is skipped entirely — so a double there would have to come
  from the shaper returning two glyphs for one offset.

An offset that lands on the wrong cell would leave the covered cell painted by
both. `!!` is worth suspecting precisely because it is *not* a ligature in
these fonts: `Ligatures.mayLigate` says two candidates side by side, so the run
is shaped, and what comes back is two ordinary glyphs — the path that is least
exercised and most likely to place them wrongly.

**The ligature switch is implicated**, from the person seeing it — which
rules out the glyph atlas and the drawing, and puts all of the above in scope.
Worth confirming once with the switch off, since that is also the workaround
for anybody hitting it in the meantime.

Worth capturing the run either way — e42eb08 records what the terminal was
given — so the exact cells, attributes and the pieces the shaper returned can
be read rather than guessed at. The probe above is four lines of CoreText and
can be pointed at whichever font is actually in use: `terminalFontName` was
empty on the machine this was seen on, so it was the bundled one.

---

Its number is where it sits in the queue, not what it is worth doing next.
Previously numbered 397.
