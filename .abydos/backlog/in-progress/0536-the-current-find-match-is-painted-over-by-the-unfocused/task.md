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

## What was done, and what was ruled out

**The paint order, and only the paint order.** The row's matches are measured
once — `searchHighlights(docLine:rect:)`, which returns the bands rather than
painting them — and painted at two depths: the other matches before `drawLine`
as before, the current one inside it *after* `drawSelection` and before the
glyphs. Painting it last decides which of the two claims wins where they
coincide, instead of leaving it to the order two functions happen to be called
in.

**"Coincides" needed no definition after all**, which is the pleasant part.
Only the match's own rectangle is covered, so a selection larger than the match
is drawn in full and still reads as a selection either side of the band sitting
on it. `images/sheet-editor-and-wide-selection.png` has lines 14–16 selected with
the current match on 14: the selection is all three lines, the match is on top of
its own characters. Skipping the selection paint where the two overlap — the
other candidate in the item — would have needed that geometry stated, and would
have had to subtract one rectangle from another with the `max(1, …)` minimum
widths both draws apply. It was not needed.

**Nothing about the fix depends on which selection colour was chosen**, so it
holds in both keyboard states by construction rather than by two fixes. Getting
a picture of the second state took a driver verb: `--find` leaves the keyboard in
the find field, and everything that puts it back in the code either closes the
bar (`closeFind` throws the matches away) or replaces the selection (a click).
`--find-next <n>` is the ordinary gesture — the bar open, the keyboard in the
text, ⌘G — and it also lands the current match in the *middle* of the cluster,
which is the reported screenshot exactly.

**The colours moved into the schemes**, which turned out to be the larger of the
two defects to look at. `images/sheet-light.png` is what "a light scheme gets
colours chosen against a dark one" looked like: the current match a grey almost
invisible on paper, the other two near-black bands with the code unreadable
inside them. All three schemes now state both keys at both lightnesses.

**`SchemeRole.optional` had to become a set.** It was a single role, and two more
optional roles could not be expressed. A rule with one member spelt as a special
case is a rule that has to be rewritten the moment there are two, so it is now a
`Set<SchemeRole>` with a derivation each: the current match midway between
`selectionBackground` and `caret` — the caret being the one colour a scheme
guarantees is visible against its own editor — and the other matches midway again
back towards the selection, which is what stops a *derived* scheme inverting them
too.

### Ruled out, and checked in passing

- **0528 is not the cause and was not touched.** The item had already
  established it; the fix confirms it from the other end, since nothing here
  reads `selectionBackgroundInactive` at all.
- **The other overlays are safe.** `currentLineBackground` and the execution-line
  band are painted first, before the highlights, so they cannot cover anything.
  Everything after the glyphs — the diagnostic squiggles, the inline diagnostic,
  the ⌘-hover underline, the fold chip — is a mark rather than a filled
  background and does not hide a band.
- **Not fixed here, and worth knowing:** the match bands are measured against the
  *whole* line even when soft wrap is on, so on a wrapped line they are painted
  at the wrong place on every row of it. `images/wrapped-line-defect.png` shows
  the current match landing on the word `word` with neither `publish` marked. The
  arithmetic is the same expressions this item moved, untouched, so this is older
  than 0536 — but it is more conspicuous now that the current match is not being
  covered up, and it wants an item of its own.
- **The execution-line band is still hardcoded** — `0x3A4A2A` in `draw` — and is
  the same class of thing as the two colours this item moved. Left alone
  deliberately: it was not in the three lines the report was about, and moving a
  colour into the schemes means choosing it in three palettes at two lightnesses,
  which is work rather than a rename.

## Steps

- [x] A verb that photographs the keyboard-in-the-editor state, since nothing
      could reach it
- [x] The current match is the most prominent of the matches on screen, with the
      keyboard in the find field *and* with it in the editor
- [x] A selection larger than the current match still draws as a selection
- [x] The two match colours are either moved into the schemes or deliberately
      left hardcoded with a written reason
- [x] Checked in all three schemes, light and dark, since the match colours were
      chosen against one background
- [x] Screenshots before and after, on a case with several matches on adjacent
      lines like the reported one
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does
