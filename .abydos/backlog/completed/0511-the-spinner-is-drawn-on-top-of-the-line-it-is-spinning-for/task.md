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

## What it is now, and what it was watched doing

One `NSStackView`, vertical, centred in the pane, spacing 8, the spinner first
and the notice under it. Nothing is offset from the centre by hand any more, so
there is no second number to keep in step with a first. The notice is an
`NSTextField` label — one line, `.byTruncatingMiddle`, `width ≤ pane − 64`.

Measured in the running app from the pane's own frames rather than from a sum
that agrees with the drawing by hand. `notice=` and `spinner=` are those two
rectangles in the pane's coordinates and are new in the driver line, because
what this item is about is where the two are *relative to each other*, and a
report naming only one of them cannot say:

    548-point pane, mid-build, a real dependency line
      notice=81,300 385x15   spinner=266,323 16x16
      → 8 points of clear air; block 300…339, centred on the pane's 319.5

    302-point pane, the same build, the same line
      notice=30,215 238x15   spinner=141,238 16x16
      → 8 points again, and the line truncates: `Working copy of ht…git
        resolved at 0.1.4`

    no spinner at all
      notice=176,312 195x15  spinner=none
      → 312…327, centred on 319.5 on its own, with no hole above it

    a model up
      drawn=548x640  notice=none  spinner=none

Eight points at both widths because eight points is the stack's spacing, and
that is the whole change: the separation is a property of the arrangement now
rather than the difference between two constants that happened to be 6 apart.

`0511-after-building.png` is a cold build in a 548-point pane on a real SwiftPM
line, `0511-after-narrow.png` the same build in a 302-point one with the line
truncated, `0511-after-waiting.png` the notice alone, `0511-after-model.png` the
model with nothing over it. The `-crop` files are the pane itself out of each.

**The lone notice had to be held still to be photographed, and that is worth
knowing.** In the shipped app a notice with no spinner exists only as
`Waiting to build …`, between the pane landing in a window and its run starting
— and `--panel-height` un-maximises the terminal panel at 0.9 s, so the editor
is not on screen until *after* that state is over. Captures at 0.3, 0.35, 0.4,
0.5, 0.6, 0.8, 0.85 and 0.88 s got a window with no editor in it; captures at
0.9, 0.92, 0.95, 1.0 and 1.2 s got a build already running. The picture here is
from a build with `provisionalRenderDelay` temporarily at 6 s — a timing knob in
`EditorViewController`, with the layout under test untouched — and the driver
line beside it (`spinner=none`, the label centred on 319.5) is the measurement
the photograph illustrates. The knob was reverted before anything was committed.

So the item's second worry is real but hardly ever *seen*: the state it is about
is over before the first frame. It still has to be right — the notice is the
pane's whole answer for as long as there is nothing else to show, and one sitting
12 points high with nothing above it would read as a mistake the one time
somebody caught it.

## The same construction is in `DiagramPaneView`, and it is left there

`constant: -18` at `DiagramPaneView.swift:127` and
`let top = (bounds.height - height) / 2 + 12` at `:516`, with comments at
`:124` and `:513` asserting a separation the arithmetic does not deliver — the
same two lines and the same two numbers. It is worse there in one way: that
pane's message sets no `lineBreakMode`, so it wraps, and since the notice's
centre is pinned at `H/2 + 12` whatever its height, every extra line adds half
a line at the top and reaches further into the spinner.

**Not fixed here.** This item's remit is the Cadova pane, and 0510 was changing
drawing in the same window while this was being done, so widening into a third
pane on the way past is how two branches end up disagreeing about one file. It
is not left unsaid either: **0512** is filed in `open/`, with the measurements
above, the two traps that cost time here — `isDisplayedWhenStopped` not setting
`isHidden`, and `positioned: .below, relativeTo:` naming a view that stops being
a sibling — and the one decision that genuinely goes the other way there. The
comment at `:513` argues *for* a message that stays put whether or not something
is turning, which is the opposite of what this item concluded, and that is worth
settling deliberately rather than by whichever pane somebody is editing.

## Ruled out, and other things found on the way

- **Changing the two numbers.** The obvious fix, and it is the fault rather than
  a fix of it: whatever pair of constants keeps a 15-point line clear of a
  16-point indicator was going to be tuned against one string at one width, in a
  pane whose notice is the build's own output and whose width the user drags.
  The measured overlap is 9.5 points, so `-18` and `+12` would have to become
  something like `-26` and `+12` — and the next two-line notice puts it back.
- **`.usesLineFragmentOrigin` being the culprit.** It is a real trap and it is
  not this one. The view is unflipped — nothing in `CadovaPreviewView`,
  `DelayedPaneView` or `ColoredView` overrides `isFlipped` — so the local called
  `top` is the rect's *bottom* edge, which is why reading the code does not
  settle anything. But the drawn block came out where the arithmetic says
  (`324.5…339.5` for a rect asked for at `y = 324.5, h = 15`), so the flag was
  not moving the text by a line. What it cost was that nobody could check the
  sums by eye, which is an argument for taking the sums out.
- **The notice drifting with its own length.** The item's own explanation, and
  it is wrong; the correction is under "Measured" above, left beside the
  original rather than replacing it.
- **0507 as an argument against a label.** It was raised in this item as a
  reason to be wary of "a third way of putting text in this pane", and it does
  not apply. 0507 was an `NSTextView()` with a zero frame and a zero text
  container, put in a scroll view — which *positions* a document view and never
  *sizes* one. An `NSTextField` label publishes an intrinsic content size and
  sizes itself, and it is not a third way in any case: `PdfFileView`, two files
  away, already has exactly this — a centred `NSTextField` notice beside a
  spinner, with `widthAnchor ≤ view − 64`. The drawn notice was the odd one out
  and the label is the house's own first answer.
- **Wrapping the notice instead of truncating it.** Rejected on what the notice
  *is*. A build line that wraps changes the block's height as the build talks,
  which moves the notice and the spinner above it several times a second; and
  the interesting parts of `Working copy of https://github.com/tomasf/Apus.git
  resolved at 0.1.4` are both ends. `.byTruncatingMiddle` is what
  `FileNoticeView` uses for a path for the same reason.
- **Keeping the notice in the same place whether or not something spins**, which
  is what `DiagramPaneView`'s comment argues for. Rejected here because the two
  states this pane alternates between are "notice with spinner" and "no notice
  at all" — a model or the compiler's message takes the whole pane — so the only
  jump is at the instant the first build starts, when the text changes from
  `Waiting to build hex-key-holder…` to `Building hex-key-holder…` anyway. A
  reserved sixteen-point gap above a lone notice would be visible in every frame
  of the state it is reserved for.
- **`isDisplayedWhenStopped` doing the hiding.** It does not: it stops the
  indicator *drawing* without setting `isHidden`, and `NSStackView` closes up
  around a hidden arranged view rather than an invisible one. Left to it, the
  lone notice would have sat low with a hole above it — the item's own second
  worry, arriving as a new defect by way of the fix for the first. `spin(_:)`
  sets `isHidden` alongside `start/stopAnimation` and is the only place either
  is touched.
- **`mountViewer` naming the spinner.** `addSubview(container, positioned:
  .below, relativeTo: spinner)` is correct only while the spinner is a sibling.
  It is inside the stack now, so it names the stack; naming a non-sibling would
  have put the model over the notice, or under nothing.
- **A unit test.** There is still no test target for `AbydosApp` — 0507 records
  why, and view code is deliberately not in `AbydosKit` — so the regression
  instrument is the driver line, as it was there. `notice=` and `spinner=` are
  the two rectangles in the pane's own coordinates, which is what makes the
  claim checkable without a window: the unfixed pane would have printed
  `notice=32,324 484x15 spinner=266,330 16x16`, and those two overlap.
- **The theme.** The notice's colour is now read once, when the label is built,
  where `draw(_:)` used to read `Theme.current` on every repaint. That is not a
  regression this pane can have: its background is handed to `ColoredView` at
  `init` and copied into a layer, so the pane has never followed a theme change
  without being rebuilt, and a notice that followed one while the background
  under it did not was the half-right version.

## Steps

- [x] Measure both placements in the running app before changing either —
      `spinner.frame` and the rect `draw(_:)` actually passes to the text
- [x] The spinner and the notice are laid out together, not against the centre
      separately
- [x] A long notice — a real build line, not a short string — does not collide
      at any pane width
- [x] The notice sits sensibly when the spinner is not shown
- [x] `drawn=` for a notice reports what is on screen rather than a second,
      differently-worded copy of the same arithmetic
- [x] Watched: a screenshot of a Cadova pane mid-build, and one between builds
- [x] `make test` and `make warnings` are clean
- [x] `DiagramPaneView` has the identical construction — decide and say here
      whether it is fixed with this or left, rather than leaving it unmentioned
- [x] Write down here what was ruled out on the way
- [x] The spec, if this changes what the project does — it may not, and saying
      so is the answer rather than skipping the step
