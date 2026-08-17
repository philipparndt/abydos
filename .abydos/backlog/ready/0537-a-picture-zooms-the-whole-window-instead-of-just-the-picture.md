# 537. A picture zooms the whole window instead of just the picture

> I dont like the zoom behaviour of imaged, as it completely depends on the
> zooming of the rest of the UI now.

Correct, and by construction. 0532 gave the picture pane two states of its own —
`Fit.pane` and `Fit.actual` — and no scale. Everything between them comes from
`Settings.shared.uiScale`, so `Zoom In` over a picture enlarges the editor font,
the sidebar rows, the tab strip and the picture together.

## This was decided on purpose, and the decision is being overruled

Worth stating plainly rather than filing as a bug nobody chose. 0532's own words,
at `ImageFileView.Fit`:

> Two states rather than a number of its own, for the reason the diagram pane
> gives at length: the app has one zoom, it is ⌘+ / ⌘- / ⌘0, and a pane that kept
> a second would be a pane where those keys did something different from
> everywhere else.

And the reason it inherited, at `DiagramPaneView.showDiagramActualSize`:

> …it puts the window's zoom back to 1× as well — the same thing `Actual Size` in
> the View menu does, since this app has one zoom and that is the item it belongs
> to.

The argument is coherent and it produced the wrong thing. **A picture is not
furniture around content; it is the content.** Enlarging it is looking closer at
the file, which is what the editor's own text zoom does for a text file — the same
act, not a different one. Coupling it to the interface's scale means you cannot
look closely at a screenshot without making the whole editor unusable, and cannot
have a large interface without a large picture.

Note the item asked for "zoom and scroll" and got scroll right: panning works,
and that half stands.

## Worth deciding

- **What ⌘+ means, and where.** The honest rule is probably "⌘+ zooms the content
  of the pane that has the keyboard" — text bigger in a text pane, picture bigger
  in a picture pane — with the interface's own scale left to Settings and the View
  menu. That is a bigger change than this one pane and it is the rule that makes
  the pane consistent rather than exceptional. The smaller change is: the picture
  keeps its own scale and ⌘+ drives it only while a picture pane has the keyboard.
  Say which, and why.
- **Whether the PDF and diagram panes follow.** They have exactly this coupling
  and nobody has complained — but nobody has complained about them the way this
  was complained about either. Leaving them means two behaviours; changing them
  means a much wider change and re-reading `spec/previews.md`. **Ask the reporter
  rather than guess**: the answer to "should a PDF behave like this too" decides
  the size of the work.
- **What `Actual Size` does about the interface.** Today it resets the window's
  zoom, which is only right while the two are the same number. Once the picture
  has its own scale, `Actual Size` must stop touching the window — and the
  diagram pane's identical line becomes wrong for the same reason if it is
  changed with it.
- **Whether a picture's scale is remembered, and against what.** `uiScale` is one
  global preference. A per-picture scale could be per tab, per file, or not
  remembered at all. Not remembered is the cheapest and probably right: a picture
  opens fitted, which is what 0532 already establishes.
- **Pinch, again.** 0532 ruled it out partly *because* zoom was the window's, so
  a pinch over a picture would have resized the whole interface. With a scale of
  its own that objection disappears, and pinch becomes the obvious gesture for a
  picture. Worth revisiting rather than treating as settled — it was settled
  against a premise this item removes.

## Steps

- [ ] A picture zooms without the rest of the window changing size
- [ ] The interface's own zoom still works, and still moves the picture's *fit*
      the way every other pane's contents scale with it
- [ ] `Actual Size` means the picture's own size and does not reset the window
- [ ] Decided and written down: whether PDF and diagram panes change with this
- [ ] Pinch reconsidered now that its objection is gone, and the answer written
      down either way
- [ ] Checked on a large screenshot and a 16-pixel icon, at two interface zooms
- [ ] Screenshots before and after — this is judged by eye
- [ ] `make test` and `make warnings` are clean
- [ ] `spec/previews.md` says what the project now does
- [ ] Write down here what was ruled out on the way
