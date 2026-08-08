# 410. The indent guide stays dark over a diff's green

In a diff, an added line is drawn on green — and the indent guide inside it is
still drawn in the editor's own guide colour, which is nearly black. The result
is a solid dark bar running down several rows of green, and it reads as
something being wrong with the file rather than as a guide.

`indentGuide` is one colour per palette (`0x2F323B` in dusk, `0x2A2118` in
abydos, `0xEAE0CC` in the light one) and it is chosen to sit a little above the
*editor* background. Nothing tells it that this row's background is not that:
the diff decides its own per-line background and draws the guide on top with
the palette's value.

Three ways out, in the order they are worth trying:

- **Derive it from the row.** The guide is "the background, lifted slightly" —
  which is what the palette value already is for an ordinary row. Computing it
  from whatever the row is actually painted with makes it right on green, on
  red, on the current-line highlight, and on anything added later.
- **Blend it.** Draw the same colour at a low alpha so the row shows through.
  Cheaper, and it goes wrong on a light palette where "lifted" means darker.
- **Leave it out of a diff.** Indentation matters least where the point of the
  view is which lines changed. The smallest change, and it gives up something.

Worth checking the same question for anything else drawn from a fixed palette
colour over a background the diff chose: the current-line highlight, the
selection, and the guide's cousins in the gutter.

---

Its number is where it sits in the queue, not what it is worth doing next.
