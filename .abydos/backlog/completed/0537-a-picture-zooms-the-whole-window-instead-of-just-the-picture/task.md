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

## Estimate

2026-08-17 19:58 — done bar the commit

## What was done

`ImageFileView.Fit` was two states and is now a state and a number: `.pane`, the
fit, and `.scale(CGFloat)`, a size somebody asked for — with `.actual` kept as a
name for `.scale(1)`, so `setFit(.actual)`, the double-click and the menu's
tick all read exactly as they did. Everything else follows from which of the two
the pane is in.

### What 1× means, in one line each

- **`.pane` is the fit times the interface's zoom**, unchanged from 0532. This
  is the half of the old rule that was right: a fitted picture is this pane's
  contents at rest, every other pane's contents grow when the interface does,
  and a picture that alone ignored ⌘+ elsewhere would shrink relative to the
  window every time somebody enlarged it. `after-09` is the 16-pixel icon fitted
  in a 150% window: `Fit · 150%`, twenty-four points.
- **`.scale(x)` is `x`, and nothing multiplies it.** A size somebody named is
  that size. This is what makes `Actual Size` mean 100% rather than 150% of a
  150% window, and it is what "a scale of its own" has to mean if it is to mean
  anything.

The two ends of that are visible together in `after-03` and `after-04`: the same
picture in the same 150% window, `Fit · 111%` and then `100%`, with `ui=150%` on
both driver lines.

### `Actual Size` no longer resets the window

`showImageActualSize` called `Settings.shared.resetZoom()` and then `setFit`.
That line was correct only while the picture's size and the interface's were the
same number — with no scale of its own, "the picture's own size" *could* only be
reached by putting the window back to 1×. `before-04` is what it was hiding: ask
for the picture's own size at a 150% interface without that reset and the old
pane drew `150%` and said so. The reset is gone; `⌘0` over a picture is
`setFit(.actual)` and touches nothing else.

The diagram pane's identical line — `showDiagramActualSize` — is untouched, and
is still correct there, because that pane still has no scale of its own.

### Where ⌘+ arrives: the responder chain, not a special case

`ImageFileView` now answers `zoomIn(_:)`, `zoomOut(_:)` and `resetZoom(_:)` —
the View menu's own selectors — and `acceptsFirstResponder` is true, so
activating a picture tab puts the keyboard in the pane and the menu's action
finds it before it finds `MainWindowController`. No branch anywhere asks "is the
front tab a picture"; the chain answers that by itself, which is the AppKit
answer and the only one that also gets the SVG split right — the source half
holds the keyboard until the drawing is clicked, and `ImageCanvas.mouseDown`
hands it over.

Worth knowing: `makeFirstResponder` on a view that does not accept it *fails*,
so before this the keyboard stayed wherever it was when a picture tab came
forward — often a code view for a file no longer on screen. Typing over a
picture used to edit an invisible file; it beeps now.

### Pinch: put back, and the objection really was the premise

0532 ruled pinch out and the reasoning was not taste — "a two-finger pinch over
a picture that resized the editor's font and the sidebar's rows would be a bug
report by lunchtime", and the only alternative then was a second scale beside
⌘+, which is the fault `PdfFileView`'s comment records. Both halves of that were
about the picture having no scale. It has one now, so a pinch has nothing to
reach but the picture. `ImageCanvas.magnify(with:)` forwards to the pane, which
multiplies continuously and clamps; `--image-zoom pinch:0.8,in` shows the whole
of the interaction with ⌘+ — 76% fitted, 137% after the pinch, 150% after the
key, because the ladder is read against the scale being drawn.

`NSEvent.magnification` still appears nowhere else in `Sources/AbydosApp`, and
that stays true. This is the pane where the picture *is* the content, which is
the same reason it is the pane that got a scale.

Not done, deliberately: zooming towards the fingers rather than the middle of
the pane. It is nicer, and it would be a second anchoring rule — ⌘+ and a pinch
would leave the picture in two different places, and `rememberAnchor` reads from
where the pane is looking precisely so there is one answer.

### The ladder

`ImageFit.zoomSteps` — 10, 25, 50, 75, 100, 150, 200, 300, 400, 600, 800 — with
`zoomIn(from:)` and `zoomOut(from:)` against the scale being **drawn** rather
than a multiplier on the fit. Two consequences worth stating: a fitted
screenshot at 76% goes to 100% and then 150%, and "press ⌘+ until it says 400%"
is the same number of presses in any window. Relative rungs would have made ⌘+
mean a different amount in every window shape.

The ends are exactly `clamp`'s bounds, so no rung is one the clamp would move
and no bound is one the ladder cannot reach. It is a *second* ladder in this
program and that is the point: `Settings.zoomSteps` runs 0.75 to 2 because that
is the useful range for type and rows, and a picture wants a tenth and eight
times over. `thePictureAndTheInterfaceZoomDifferently` asserts they are not the
same list, so a later tidy-up cannot merge them without saying so.

### Not remembered

Not per file, not per tab beyond the tab's own life, nowhere on disk. A picture
opens fitted, which is the answer to "what is in this file"; a scale is a way of
looking at *this* picture for a moment. Remembering it would need a store, would
have to be forgotten on a rename and a delete, and would open a picture at a
size chosen last week in a differently shaped window — 0532's own argument, and
it survives this item intact because it was never the part that was wrong.

### The PDF and diagram panes are now inconsistent with this, on purpose

They have exactly the coupling that was complained about: ⌘+ over either is the
interface's zoom, which their fit multiplies. **They were not changed, and that
leaves two behaviours in one window.** This is deliberate and it is waiting on
an answer, not on work.

The wider rule, if the answer is yes, is one sentence: **⌘+ zooms the content of
the pane that has the keyboard** — text bigger in a text pane, page bigger in a
PDF pane, drawing bigger in a diagram pane — with the interface's own scale left
to Settings and to a View-menu item that says so. What it would cost, now that
one pane has been done and the shape is known:

- `PdfFileView` and `DiagramPaneView` each take the same treatment as this pane:
  `acceptsFirstResponder`, the three selectors, a scale of their own instead of
  `Theme.current.scale`, and `showDiagramActualSize` losing its `resetZoom()`.
  Both already have a `Fit` of their own to hang it on. Half a day each.
- The editor's own text zoom becomes the third case and is the one that is not
  yet written: today a text pane has no scale apart from the interface's, so
  "⌘+ zooms the text" means a font size per pane or per tab, and where *that*
  is remembered is a question this item did not have to ask. Call it a day.
- The View menu needs an item for the interface's zoom that ⌘+ no longer
  reaches, and the four panes' context menus need to keep saying the truth.
- `spec/previews.md` and `spec/editor.md` both move, and the paragraph above
  about the two behaviours comes back out.

Two to three days, and the reason to know that before deciding is that "should a
PDF behave like this too" is a one-word answer with a three-day tail.

## What was ruled out

- **Making the wider change now.** The scope was decided before the work
  started, and the reason holds: nobody has complained about the PDF or the
  diagram pane, and a change that size taken on a guess is a change nobody
  asked for. What is written above is the sizing, so the decision can be taken
  with it.
- **Rungs relative to the fit** — `pictureZoom` multiplying `.pane`'s basis.
  It keeps the enum simpler and it makes ⌘+ mean a different amount in every
  window shape, so the caption and the number of presses stop agreeing with
  anything. The rungs are absolute for the same reason every picture viewer's
  are.
- **`Actual Size` following the interface's zoom** — `.scale(x)` times
  `Theme.current.scale`, which would have kept `.pane` and `.scale` symmetrical.
  It reintroduces exactly the menu item that lies about the number in its own
  name, which is what 0532 papered over with `resetZoom()`. The asymmetry is the
  honest half: a *fit* is a relationship with the pane and follows the window; a
  *size* is a fact about the file and does not.
- **A branch in `MainWindowController.zoomIn` asking whether the tab in front is
  a picture.** It is one line shorter and it is wrong about the SVG split, where
  the picture is in front and the keyboard is in the source. The responder chain
  is the question "which pane is being looked at" already asked and answered.
- **`NSApp.sendAction(_:to:from:)` in the driver.** It starts at the **key**
  window and a driven run has none: every step came back `reached nobody` while
  the pane plainly held the keyboard, which cost a build to work out.
  `--image-zoom` walks the responder chain itself — first responder, then
  `nextResponder` outwards — and prints who took each step, so `took=
  ImageFileView` against `took=MainWindowController` is the whole item in one
  word.
- **A driver verb that calls `pane.zoomIn(nil)`.** It would pass with the
  routing deleted, which makes it a test of nothing. The arithmetic is already
  tested without a window in `ImagePreviewTests`; what needed a running app was
  *where the key arrives*.
- **Zooming towards the pointer on a pinch.** Above.
- **Touching 0532's scroll and pan work.** It was right and none of it moved.

## Pictures

All 1400 × 900 on a 2× screen, dark, a `2800 × 1800` screenshot and a `16 × 16`
icon. The driver line under each is in the commit; the two numbers to read are
`scale=` (the picture) and `ui=` (the interface).

Before:

- `before-01-fitted-ui100.png` — `Fit · 76%`, the starting point both ways.
- `before-02-cmd-plus-twice.png` — **this is the report.** ⌘+ twice: the tree's
  font, the tab strip and the caption are all a quarter larger, and the picture
  went 76% → 93%.
- `before-03-fitted-ui150.png` — the interface at 150%, `Fit · 111%`.
- `before-04-actual-ui150.png` — the picture's own size asked for at a 150%
  interface: `150%`, which is what `Actual Size` had to reset the window's zoom
  to avoid saying.
- `before-05-icon-fitted-ui100.png`, `before-06-icon-at-max-window-zoom.png` —
  the icon at sixteen points, and then at the very top of the window's zoom,
  which is thirty-two points and the whole interface at 2×. There was no way to
  see a 16-pixel icon larger than that.

After:

- `after-01-fitted-ui100.png` — `Fit · 76%`. Identical to before-01, which is
  the point: nothing about opening a picture changed.
- `after-02-zoomed-in-twice-ui100.png` — the pair to before-02. ⌘+ twice is
  `150%`, both scrollers live, and the tree, the strip and the caption are
  pixel-for-pixel what they are in after-01.
- `after-03-fitted-ui150.png`, `after-04-actual-ui150.png` — `Fit · 111%` and
  then `100%` in the same 150% window. The fit still follows the interface; the
  chosen size does not, and the window stays at 150% either way.
- `after-05-icon-fitted-ui100.png`, `after-06-icon-800-ui100.png` — sixteen
  points, then `800%` at a hundred and twenty-eight, pixels drawn as pixels on
  the checkerboard, with the window around it untouched. Against before-06 this
  is the clearest single pair on the item.
- `after-07-icon-800-ui150.png` — the same 800% in a 150% window: still a
  hundred and twenty-eight points, because a chosen size is a chosen size.
- `after-09-icon-fitted-ui150.png` — and the fitted icon in that window is
  `Fit · 150%`, twenty-four points, which is the other half of the rule.
- `after-08-pinch-then-in.png` — a pinch to 137% and then ⌘+ to 150%.
- `after-10-zoomed-out.png` — ⌘- twice from the fit, `50%`, smoothed.
- `after-11-svg-400.png` — an SVG at `600%`, redrawn rather than magnified, with
  no blur at all.

## Steps

- [x] A ladder of sizes a picture zooms through, in `ImageFit`, so the steps can
      be checked without a window
- [x] A picture zooms without the rest of the window changing size
- [x] ⌘+ reaches the picture rather than the window when the picture pane has
      the keyboard — which means the pane has to be able to *have* the keyboard
- [x] The interface's own zoom still works, and still moves the picture's *fit*
      the way every other pane's contents scale with it
- [x] `Actual Size` means the picture's own size and does not reset the window
- [x] Decided and written down: whether PDF and diagram panes change with this
- [x] Pinch reconsidered now that its objection is gone, and the answer written
      down either way
- [x] A driver verb that drives the picture's zoom through the *menu's own
      action*, so the routing is checked and not only the arithmetic
- [x] Checked on a large screenshot and a 16-pixel icon, at two interface zooms
- [x] Screenshots before and after — this is judged by eye
- [x] `make test` and `make warnings` are clean
- [x] `spec/previews.md` says what the project now does
- [x] Write down here what was ruled out on the way
