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

which is the property the code relies on and states.

**What it does instead is substitute, and the ink is on the last glyph.**
Shaping the same text with `calt` on and off gives different glyphs, and the
shape of the difference is the thing to know:

    "!!"  calt on [12137, 11948]         off [5, 5]
    "..." calt on [12137, 12137, 11934]  off [18, 18, 18]
    "->"  calt on [12137, 11919]         off [17, 34]
    "!="  calt on [12137, 11950]         off [5, 33]
    "a!"  calt on [69, 5]                off [69, 5]      (nothing to join)

Glyph 12137 is the first glyph of *four different pairs* whose first characters
are `!`, `.` and `-`, so it is not any of them: it is the blank carrier these
fonts use, and the whole ligature's ink lives on the last glyph, reaching back
over the cells before it. Which means the cells a ligature covers are
**supposed** to draw a blank glyph rather than nothing, and one cell drawn from
the per-cell path instead of from the shaper puts a real `!` under ink that
already covers it. That is what "the first of the two is painted double" is.

**Not reproduced yet, and that is a fact about the bug.** With ligatures on,
photographed at 1× and 2×: the same `repository("!! app/build/\n")` line in the
editor, the same text in a terminal pane, and the same line after typing into
the file to force an incremental redraw. All three render correctly. So it is
not the text, the font, or the zoom — something about the state when it happens
matters, and a first paint of a freshly opened file never has it. A repaint
that covers part of a line, over ink already there, is the obvious candidate
and is what to try next.

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
