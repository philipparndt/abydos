# 511. The spinner is drawn on top of the line it is spinning for

> the progress indicator collides with the text

Reported with a screenshot of a Cadova pane mid-build: the spinner sits over
the middle of `Building for debugging…`, its spokes between the letters.

## Why

`CadovaPreviewView` places the two things independently, against the same
centre, in two different ways:

    spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18)

    let top = (bounds.height - height) / 2 + 12
    text.draw(with: NSRect(x: 32, y: top, width: width, height: height),
              options: [.usesLineFragmentOrigin])

The spinner is a fixed 18 points from the centre of the view. The notice is
drawn from an origin worked out from **its own measured height**, so where it
lands moves as the text does — a longer notice that wraps to two lines moves
further than a short one, and `.usesLineFragmentOrigin` means the rect's origin
is the top of the first line fragment rather than the bottom of the block. Two
placements that were tuned against each other once, for one length of one
string, in one size of pane.

The class comment says the intent plainly — *"One line, in the middle, with the
spinner over it"* — so the arrangement is meant to be a stack. It is not built
as one.

## What it should be

One arrangement that measures both, so they cannot overlap whatever the notice
says or how tall the pane is. The notice is **build output** — `show(notice:
line)` is fed the last line the build printed — so it is arbitrary text of
arbitrary length, not a fixed string, and it truncates in the middle rather
than wrapping only by luck.

## Measured before anything was changed

Printed from the running app, cold build of a Cadova package in a split, with a
temporary probe in `reportForTesting` reading `spinner.frame` and the very rect
`draw(_:)` hands to the text:

    bounds=(0, 0, 548, 640)
    spinner=(266, 330, 16, 16)          → y 330…346, centre 338
    noticeRect=(32, 324.5, 484, 15)     → y 324.5…339.5, centre 332

The pane's centre is y = 320. So:

- **`constant: -18` puts the spinner 18 points *above* the centre**, not below.
  Auto Layout's geometry runs top-down whatever the view's own flippedness —
  `topAnchor + 20` is 20 points down in an unflipped view too — so a negative
  constant on `centerYAnchor` is upward in this view's y-up coordinates.
- **The notice's centre is 12 points above the centre**, so the two centres are
  **6 points apart, both pushing the same way**, and a 16-point indicator over a
  15-point line at 6 points' separation overlaps on **y 330…339.5 — 9.5 points**.

That is the reported picture and it is not a near miss: two thirds of the
spinner's height is inside the line of text. `0511-before.png` is that run, and
`0511-before-crop.png` is the pane itself, spokes between the `7` and the `/` of
`[537/628]`.

**The arithmetic in the "Why" above is wrong and is left there rather than
edited**, because the wrong reading is the tempting one. The notice's rect is
`y = (H - h)/2 + 12` with height `h`, so it spans `[(H-h)/2 + 12, (H+h)/2 + 12]`
and its **centre is `H/2 + 12` whatever `h` is** — the `-h/2` in the origin and
the `+h/2` of the rect's own extent cancel. The notice does not drift with its
own length. What a taller notice does is grow *into* the spinner from both
directions, which is worse rather than different: the fault is there at one line
already, and every extra line makes it deeper.

Two more things the numbers settle. The view is **unflipped** — nothing in
`CadovaPreviewView`, `DelayedPaneView` or `ColoredView` overrides `isFlipped` —
so the local called `top` is the rect's *bottom* edge, which is why the
arithmetic is so hard to check by reading. And `drawn=484x15` came out of a
*second* copy of the measurement in `drawnArea`, which uses the same width and
the same `boundingRect` but **without the paragraph style**, so the number
feeding the driver was measuring the string differently from the way the pane
drew it.

## Worth deciding

- **Whether the notice stays drawn in `draw(_:)` at all.** A label in a stack
  view beside the spinner is the shape this wants, and it would take the
  arithmetic out entirely. Against that: `draw` is already there and the pane
  has one other text view (the failure text) whose own sizing was 0507's bug —
  worth reading that item before adding a third way of putting text in this
  pane.
- **What it looks like with no spinner.** `isDisplayedWhenStopped` is false, so
  the notice is alone between builds and should not sit at an offset that only
  makes sense when something is spinning above it.

## Estimate

2026-08-16 19:39 — about two hours left

## Steps

- [x] Measure both placements in the running app before changing either —
      `spinner.frame` and the rect `draw(_:)` actually passes to the text
- [x] The spinner and the notice are laid out together, not against the centre
      separately
- [ ] A long notice — a real build line, not a short string — does not collide
      at any pane width
- [ ] The notice sits sensibly when the spinner is not shown
- [x] `drawn=` for a notice reports what is on screen rather than a second,
      differently-worded copy of the same arithmetic
- [ ] Watched: a screenshot of a Cadova pane mid-build, and one between builds
- [ ] `make test` and `make warnings` are clean
- [ ] `DiagramPaneView` has the identical construction — decide and say here
      whether it is fixed with this or left, rather than leaving it unmentioned
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if this changes what the project does — it may not, and saying
      so is the answer rather than skipping the step
