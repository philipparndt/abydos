# 536. The current find match is painted over by the unfocused selection

> the highlighted item in the search is actually dimmed instead of highlighted.
> This leads to confusion what it the active item.
>
> example: the item in line 289 is the current search occurence

The screenshot is a `Makefile` with three matches of `publish` on lines 288, 289
and 290. The current one, 289, is the **darkest of the three**. The two it is
supposed to stand out from are brighter than it is.

**This entry first claimed the report was about the results list and the
`hasKeyboard` rule.** It was not, and the screenshot settled it: this is
find-in-file inside the editor, a different mechanism with a different fault. The
list reasoning is gone from this item rather than left to mislead. What follows is
measured.

## The paint order, which is the whole of it

`CodeView.draw` paints a row in this order:

1. `drawSearchHighlights(docLine:rect:)` — line 597. Every match on the line gets
   a background, and the current one is deliberately the strong colour. Its
   comment says so: *"The current match is stronger, so it is findable at a
   glance among the others."*
2. `drawLine(…)` — line 599, which calls `drawSelection(…)` at line 662 under the
   comment *"Selection sits behind the glyphs."*

Both are true separately and wrong together. **The current match *is* the
selection** — revealing a match selects it — so step 2 paints over exactly the
pixels step 1 just made strong. And while somebody is typing in the find field
the editor is not the first responder, so `Theme.selection(.text, hasKeyboard:
false)` hands back the *unfocused* colour.

Against `editorBackground` in dark `abydos`:

    #C77B3B   5.21   what drawSearchHighlights paints for the current match
    #5A4A2A   2.02   what it paints for every other match
    #3A2E24   1.31   selectionBackgroundInactive, which then covers the current one

So the match that is meant to be strongest ends up the weakest of the three, and
the ones it is meant to be found among sit above it. The screenshot is that
arithmetic.

## Not caused by 0528, and slightly improved by it

Worth recording, because 0528 landed the same day and is the obvious suspect.
Before it, an unfocused text selection used `selectionInactive` — `#2A2018`, which
0528 measured at 1.17 against the editor background. So the overpaint used to be
*darker* still. 0528 lifted it to 1.31 and the inversion survived, because the
inversion is not about how dim the unfocused selection is; it is about the
selection being painted over the current match at all.

Two things follow. The fault has been there as long as find-in-file has, and
fixing 0528's colour further would not fix it — at any value below `#C77B3B` the
current match is still the one being dimmed by being current.

## Worth deciding

- **Which of the two should win where they coincide.** The current match being
  strongest is the point of having a current match; a selection band is a weaker
  claim. Skipping the selection paint where it exactly coincides with the current
  match is one answer, and drawing the current match *after* the selection is
  another and probably the simpler one — but note the selection can be *larger*
  than the match (somebody may have extended it), so "coincides" needs saying
  precisely rather than assumed.
- **Whether the match colours belong in the scheme.** `0xC77B3B` and `0x5A4A2A`
  are hardcoded in `drawSearchHighlights`, so the three schemes cannot disagree
  about them and a light scheme gets colours chosen against a dark one. That is a
  separate defect visible in the same three lines, and the fix will be reading
  those pixels anyway. `#5A4A2A` at 2.02 against a *light* background is worth a
  look before deciding whether to widen the scope.
- **What happens with the keyboard in the editor.** Then the selection is
  `selectionBackground` — `#4A2C0E`, which 0528 measured at 1.47 — still below
  the current match's 5.21, so the inversion is milder but the same shape. Any
  fix has to hold in both states, not only the one in the screenshot.
- **Whether other overlays have the same problem.** `currentLineBackground` is
  painted before the highlights and so is safe, but it is the same class of
  question and cheap to check while in there.

## Steps

- [ ] The current match is the most prominent of the matches on screen, with the
      keyboard in the find field *and* with it in the editor
- [ ] A selection larger than the current match still draws as a selection
- [ ] The two match colours are either moved into the schemes or deliberately
      left hardcoded with a written reason
- [ ] Checked in all three schemes, light and dark, since the match colours were
      chosen against one background
- [ ] Screenshots before and after, on a case with several matches on adjacent
      lines like the reported one
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
