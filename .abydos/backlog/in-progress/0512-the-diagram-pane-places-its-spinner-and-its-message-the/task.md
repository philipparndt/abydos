# 512. The diagram pane places its spinner and its message the same way 0511 did

Found while fixing 0511 and written down there rather than fixed there, because
0511's remit was the Cadova pane and another item was changing drawing in the
same window at the time.

`DiagramPaneView` has the identical construction, line for line:

    // Above the message rather than behind it: both are shown while a
    // diagram is being drawn, and centred on the same point the text
    // runs straight through the spinner.
    spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18)
                                                      // DiagramPaneView.swift:127

    // Below the spinner's place, whether or not one is turning: the message
    // sits in the same spot either way, so it does not jump when the drawing
    // finishes.
    let top = (bounds.height - height) / 2 + 12
    text.draw(with: NSRect(x: 32, y: top, width: width, height: height),
              options: [.usesLineFragmentOrigin])          // DiagramPaneView.swift:516

**Both comments assert a separation the arithmetic does not deliver.** Measured
in the app for 0511, on the Cadova pane, which has these two placements and
these two numbers and nothing else in common:

    spinner    y 330…346   centre 338      pane 548 × 640, centre y = 320
    notice     y 324.5…339.5   centre 332

`constant: -18` is 18 points *above* the centre — Auto Layout's geometry is
top-down whatever a view's own flippedness — and the notice's centre is
`(H - h)/2 + 12 + h/2 = H/2 + 12`, so the two centres are **6 points apart, both
pushing the same way**, and a 16-point indicator over a 15-point line overlaps
on 9.5 of them.

Two differences from 0511, and the first makes this one worse rather than
better:

- **The diagram pane's message wraps.** It sets no `lineBreakMode`, so a
  complaint of two or three lines grows *into* the spinner from both directions
  — the notice's centre is pinned at `H/2 + 12` whatever its height, so every
  extra line adds half a line at the top.
- **The message is a complaint rather than build output**, so it is at least
  text somebody wrote, not whatever SwiftPM said last.

## Measured in this pane, before anything was changed

Printed from the running app by `--diagram-watch`, which is new here and is
below. `notice=` is the rect `draw(_:)` hands the text and `spinner=` is
`spinner.frame`, both in the pane's own coordinates, so whether they overlap is
arithmetic on the line. The pane is unflipped, so a larger y is further **up**
the screen.

    808 × 627 pane, centre 313.5 — a Mermaid fault on one line
      notice=32,318.0 744x15    → y 318…333,     centre 325.5
      spinner=396,324.0 16x16   → y 324…340,     centre 332
      → overlapping on y 324…333, nine points of a sixteen-point indicator

    448 × 693 pane, centre 346.5 — mid-render, "Nothing to draw yet."
      notice=32,351.0 384x15    → y 351…366
      spinner=216,357.0 16x16   → y 357…373
      → the reported picture, and `0512-before-crop.png` is it: the spokes
        between the "to" and the "draw"

    448 × 667 pane, centre 333.5 — PlantUML's install hint, three lines
      notice=32,323.0 384x45    → y 323…368
      spinner=216,344.0 16x16   → y 344…360
      → the indicator is *entirely* inside the message

    228 × 653 pane, centre 326.5 — the same Mermaid fault, four lines
      notice=32,308.5 164x60    → y 308.5…368.5
      spinner=106,337.0 16x16   → y 337…353
      → entirely inside again, and further in

So this pane's numbers are 0511's numbers: **the message's centre is `H/2 + 12`
and the indicator's is `H/2 + 18` at every width and every height**, six points
apart and both pushed the same way. 0511's correction holds here too — the
`-h/2` in the origin and the `+h/2` of the rect's own extent cancel, so the
message's centre does not drift with its length. What its length does is what
the last two readings show: the block grows into the indicator from both
directions, and by three lines the indicator is not overlapping the message, it
is inside it.

## What it should be

What 0511 did to `CadovaPreviewView`: one `NSStackView`, vertical, centred, the
indicator first and the message under it, so the separation is the stack's
spacing rather than the difference between two constants. Read that item first —
it has the measurements, and two traps that cost most of an hour:

- `isDisplayedWhenStopped = false` stops the indicator drawing but does **not**
  set `isHidden`, and a stack only closes up around a hidden arranged view — so
  the indicator has to be hidden explicitly or a message with nothing turning
  above it gets a sixteen-point hole.
- Anything that adds a subview `positioned: .below, relativeTo: spinner` has to
  name the stack instead once the spinner is inside one, or it is naming a view
  that is not its sibling.

Unlike the Cadova pane, this one's comment at `:513` argues *for* the message
staying put whether or not something is turning. That is a real decision and it
goes the other way in 0511, where the pair is centred as a block and a lone
message is centred on its own — worth settling deliberately rather than by
whichever pane is being edited.

## Steps

- [x] Measure this pane's own two rectangles in the app, rather than assuming
      0511's numbers carry over
- [x] The indicator and the message are laid out together
- [x] A message of two or three lines does not reach the indicator
- [x] Decide whether the message stays put or re-centres when nothing is
      turning, and correct the comment at `:513` either way
- [x] Decide whether the message goes on wrapping or truncates as 0511's does,
      and say why on its own terms rather than by what 0511 concluded
- [x] The message follows a theme change and a ⌘+ as it did while it was drawn
- [x] The indicator is out of the arrangement before anything has ever spun, not
      only after something has stopped — found by the line above, and new here
- [ ] Watched, with a screenshot of a diagram pane mid-render
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if this changes what the project does

## Estimate

2026-08-16 21:45 — about two hours left
