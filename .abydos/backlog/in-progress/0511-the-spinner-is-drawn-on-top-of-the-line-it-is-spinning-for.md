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

- [ ] Measure both placements in the running app before changing either —
      `spinner.frame` and the rect `draw(_:)` actually passes to the text
- [ ] The spinner and the notice are laid out together, not against the centre
      separately
- [ ] A long notice — a real build line, not a short string — does not collide
      at any pane width
- [ ] The notice sits sensibly when the spinner is not shown
- [ ] `drawn=` for a notice reports what is on screen rather than a second,
      differently-worded copy of the same arithmetic
- [ ] Watched: a screenshot of a Cadova pane mid-build, and one between builds
- [ ] `make test` and `make warnings` are clean
- [ ] `DiagramPaneView` has the identical construction — decide and say here
      whether it is fixed with this or left, rather than leaving it unmentioned
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if this changes what the project does — it may not, and saying
      so is the answer rather than skipping the step
