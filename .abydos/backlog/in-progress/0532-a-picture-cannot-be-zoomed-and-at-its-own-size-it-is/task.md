# 532. A picture cannot be zoomed, and at its own size it is cropped rather than scrolled

> when showing images, it should be possible to zoom and scroll. Currently it is
> always zoom to fit

The report is right and the cause is narrower than "always fits". There *is* a
scroll view, and there *is* a way to leave the fit — `ImageFileView.mouseDown`
swaps between fitting the pane and 1:1 on a double-click. Two things stop that
from being what was asked for.

## What is actually wrong

**The document view is pinned to the pane, so scrolling has nowhere to go.**
`ImageFileViewer` installs the picture in an `NSScrollView` with both scrollers,
and then:

    NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification,
        object: scrollView.contentView, …
    ) { … imageView.setFrameSize(scrollView.contentSize) }

The document is resized to the *content* size on every frame change, so it is
never larger than the visible area and the scrollers never have anything to
scroll. The comment above it says the picture "fits the pane it is given, so the
document is the pane until somebody asks for the picture's own size" — but
nothing ever grows it when they do ask. So the double-click to 1:1 draws a
2560-wide screenshot at 1:1 inside a pane-sized document and **crops it**, which
is worse than fitting it: the scroll view's own doc comment claims this is "what
makes a picture shown at its own size pannable rather than cropped", and it is
the line that prevents exactly that.

**There is no zoom, only a toggle.** `chosenScale` is `nil` or `1` and nothing
else can set it. There is no way to ask for 50%, or 400% to look at a few
pixels, which is the other half of the request.

## The rule already exists, and this pane is the one that did not get it

`ImageFit` has two zoom rules and the difference between them is written down at
length:

- `fitScale(image:in:zoom:)` caps the zoom at what the pane can hold. For a pane
  that cannot scroll, that is right.
- `widthScale(width:paneWidth:zoom:)` does not cap, and its comment says why:
  *"Where the pane scrolls, that cap is exactly wrong: ⌘+ would stop having any
  effect the moment the drawing filled the pane, which is precisely when
  somebody presses it."* It fits to the **width** alone, so a tall picture is
  read by scrolling down it. It clamps to 0.1…8.

`PdfPreview.scale` and `DiagramPaneView` are both that function under their own
callers — the comment is explicit that one rule with two callers is the point,
"rather than two rules that agree today". A picture pane scrolls, so it wants
the same rule and would be the third caller. **This is joining something, not
inventing something.**

`ImageFit.caption` already renders a percentage and is already called.

## Worth deciding

- **What the gesture is.** The app has no pinch-to-zoom anywhere —
  `NSEvent.magnification` appears nowhere in `Sources/AbydosApp`. PDF and diagram
  panes zoom with the app's own ⌘+/⌘−, so a picture doing the same is consistent
  and free. Pinch is what people expect of a picture specifically, and adding it
  here alone makes it the one pane that has it. Decide, and say which.
- **What the double-click means afterwards.** It is a fit ↔ 1:1 toggle today and
  that is a genuinely good gesture for a scaled-down screenshot. It can stay,
  but "1:1" has to start meaning *1:1 and scrollable*.
- **What 100% means on a Retina screen.** `pixelSize` is deliberately in pixels
  because `NSImage.size` is in points and "a picture from a Retina screenshot
  claims to be half of what it holds". Drawing at `scale: 1` puts one image pixel
  on one *point*, so a 2× screenshot at "100%" is showing at half size on a 2×
  display. The caption says `100%` either way. Whatever is chosen, the caption
  and the drawing must agree.
- **Whether a bitmap should smooth or not above 100%.** `ImageFit`'s existing
  comment argues that blowing a bitmap up "gives the blur that fitting it never
  did" — an argument against zooming past 1:1 at all, now overruled by the
  request. But the reason somebody zooms a screenshot to 400% is to see the
  pixels, and smooth interpolation hides exactly what they are looking for.
  `NSImageInterpolation.none` above 100% is worth trying against `.high`.
- **SVG is in this pane too.** `FilePreview.kind` sends `.svg` to `.image`, and
  an SVG is drawn from instructions — it has no pixel count, so `pixelSize` falls
  back to its size in points, and it can be zoomed without any blur at all. Check
  what the clamp and the caption do for one; it is the case where zooming is
  free and unlimited.
- **Whether the fit should follow the pane after a zoom.** Today `setFrameSize`
  redraws on every resize, which is right while fitted and wrong once somebody
  has chosen a scale — resizing the window should not silently rescale a picture
  they have set to 200%.

## Estimate

2026-08-17 15:27 — done bar the commit

## What was done

The pane is now built the way the diagram pane is, because the diagram pane had
already worked all of this out. `ImageFileView` *is* the tab's content view
rather than the document inside a scroll view of somebody else's: it owns the
scroll view, a canvas that is the document, and the caption at the foot — which
used to be a subview of the document, so it would have scrolled away with the
picture the moment the picture became larger than the pane.

`ImageFileViewer`, and with it the frame-change observer that resized the
document to `contentSize`, is gone. The document is `ImageFit.documentSize`: the
scaled picture plus its margin, or the pane, whichever is larger in each
direction. That is the whole fix for the crop.

### The gesture: ⌘+ / ⌘-, a right-click menu, and the double-click. No pinch.

The app has one zoom. It is ⌘+ / ⌘- / ⌘0, it is remembered across a relaunch,
and the PDF pane and both diagram panes follow it. A picture now does too, and a
right-click over one says so out loud — `Zoom In`, `Zoom Out`, `Actual Size`,
`Fit to Window` — the same four items the diagram pane offers, with the same
words for the three that mean the same thing.

**Pinch was considered and rejected, and the reason is not consistency for its
own sake.** `NSEvent.magnification` appears nowhere in `Sources/AbydosApp`, so
adding it here would make the picture pane the one place in this program where a
gesture changes how large something is. That is not a free win, because this
app's zoom is *one number for the window*: a pinch would either have to drive
that number — and a two-finger pinch over a picture that resized the editor's
font and the sidebar's rows would be a bug report by lunchtime — or it would have
to keep a second scale of its own, which is precisely the "second zoom sitting
beside ⌘+" the PDF pane's own comment records as the bug the diagram panes had
twice in one week. Neither is worth a gesture. If pinch is ever wanted it wants
to be wanted for every pane at once, and that is a different item.

The double-click stayed, and it means something different now: `1:1` used to be a
crop and is now the whole picture with somewhere to scroll. Two-finger scrolling
pans it, which is what a scroll view was there for all along.

### Retina: 100% is the size the file *says* it is

The report's premise was almost right and pointed the wrong way. `pixelSize` is
in pixels, and drawing it at `scale: 1` puts one image pixel on one *point* — so
a 144-dpi screenshot at "100%" was not showing at half size, it was showing at
**twice** the size of the thing it was a screenshot of, and being interpolated to
get there. The `2560 × 1600` screenshot at "100%" occupied 2560 points, which is
5120 pixels of a 2× display for 2560 pixels of file.

So the pane now draws `NSImage.size` — the size in points a file declares — and
keeps `pixelSize` for the caption and for the interpolation decision. That makes
100% mean what Preview means by it and what `PdfPreview.scale`'s comment already
claimed for a page ("a PDF states its own page size in points and 100% is what
that size means"), and it is the sharpest a picture can be shown: one pixel of a
Retina screenshot on one pixel of the screen.

The caption and the drawing now agree, and it is worth writing down *how* they
agree, because at first sight the number looks like it moved. The fitted
screenshot used to read `42%` and now reads `Fit · 83%` — and it is the same
number of points on screen either way. `42%` was of the pixel count while the
drawing was of the points; `83%` is of the stated size, and on this 2× screen it
is also 83% of the pixel count. The old number was wrong under both readings and
the new one is right under both.

Nothing about a 72-dpi picture changed: its stated size *is* its pixel count, so
a 16-pixel icon is still drawn at sixteen points and still not blown up.

### Interpolation: none above the file's own pixels, smooth below

`NSImageInterpolation.none` when the picture is being drawn larger than its own
pixels on this screen, `.high` when smaller. **Decided against the pixel count
rather than against the percentage**, which is what makes it right at 100% as
well as above it: a 72-dpi picture at its own size covers each of its pixels with
a 2 × 2 square of screen pixels, and that square is either honest or a smudge.

Judged by looking, and the pictures are attached. `interpolation-none-against-
smooth.png` is the same 200% magnification of a one-pixel checkerboard both
ways: nearest keeps it a checkerboard, smooth turns it into a flat mustard
smear — and a smear is exactly what somebody zooming to 200% is trying to see
past. `icon-interpolation-before-and-after.png` is the sixteen-pixel icon at
100%, blurred before and crisp now; it is the clearest single picture on this
item. Non-integer factors were checked too — `after-07` is `Fit · 158%`, where
nearest gives hairlines of uneven spacing but every one of them still a hairline,
which beats all of them being grey.

A drawing is never nearest: an SVG has no pixel to preserve, `NSImage` renders it
afresh at whatever size it is asked for, and `after-06` is one at 200% with the
diagonal hairline still one pixel wide.

### Resizing after a zoom, and what `Fit` means

A picture in `Fit` re-fits when the window is resized, because that is what Fit
*is*, and the caption says `Fit` so it is not silent. A picture at a size
somebody chose is left at that size. This is the diagram pane's answer exactly,
including the part that looks odd written down: `Fit · 158%` can be larger than
the pane, because the fit is a basis and the zoom multiplies it — capping it
there is the bug this item was filed about.

A zoom or a resize keeps the middle of the pane on the same part of the picture.
Without that, ⌘+ at 400% threw somebody back to the top left of a picture they
were looking into the middle of.

### `widthScale`: the basis is a picture's own, the zoom is shared

Not reused directly, and the reason is written into `ImageFit.paneScale`: a PDF
and a diagram are *read*, downwards, so fitting their height is how a page ends
up a stamp in the middle of a window — while a picture is *looked at*, and the
question it answers on opening is "what is in this file". Fitting a portrait
photograph to the width alone would open it as the top third of itself. So the
basis consults both directions, as it always did.

Everything after the basis is shared, which is the part that mattered: the zoom
multiplying it and the bounds are now `ImageFit.zoomed`, and `widthScale` routes
through the same function. One place where ⌘+ multiplies, one clamp,
`theThreePanesAgreeAboutTheZoom` asserting that a picture and a page at the same
basis are the same number.

**And the capped rule is gone.** `fitScale(image:in:zoom:)` took `min(zoom,
room)` for a pane that could not scroll, and it turned out to have no caller left
in `Sources` at all — only tests. Nothing in this program is a pane that cannot
scroll any more. Leaving a dead second answer to ⌘+ next to the live one is how
the wrong one gets called, so it was removed rather than kept, and its tests now
assert the uncapped rule.

## What was ruled out

- **Pinch to zoom.** Above. It would be the only pane with it and it would have
  to fight or duplicate the window's one zoom.
- **Fitting to the width, like the PDF and diagram panes.** Above: it would open
  every portrait picture scrolled. A tall full-page screenshot is the case that
  argues for it, and the answer for that is now ⌘+ and a double-click, which is
  what the item asked for in the first place.
- **A zoom of the pane's own, remembered per file.** The diagram pane's argument
  applies unchanged: it would need a store, would have to be forgotten on rename
  and delete, and would open a picture at a size chosen last week in a
  differently shaped window.
- **Two rules that agree today.** See `zoomed`.
- **Buttons in the corner of the pane.** They would sit over the picture, and
  they would be a second zoom beside ⌘+ — the fault `PdfFileView`'s comment
  records from the diagram panes. A right-click menu names the same commands
  without occupying the picture.
- **A blank `--image-fit` verb that only reports a percentage.** The driver
  prints the picture, the document and the visible rectangle together, because
  no capture of a picture can show whether the thing under it is larger than the
  hole it is seen through. That line is what proved the bug (`picture=2560x1600
  document=1099x789 visible=1099x789`) and what proves the fix
  (`document=1312x832 visible=1084x741 at=228,0` after panning to the corner).

## What cost the most, and is worth not paying twice

A picture tab lost its **tab**. The strip above the picture drew nothing at all,
while `layoutReportForTesting` insisted it was visible, on top, alpha 1, holding
one item at `{{0, 0}, {155, 34}}` inside bounds `{{0, 0}, {1099, 34}}` — and a
text file in the same window drew its tab perfectly. Two wrong theories were
paid for on the way (a layout pass that asked for another for ever, twice over:
an unconditional `scroll` and an unconditional `stringValue`; both are real
faults and both are now guarded, and neither was this one).

What it was: `draw(_ dirtyRect:)` filled `dirtyRect`, and a dirty rectangle is
not promised to lie inside the view it is handed to. The capture path hands over
one covering the whole window, so the pane painted a band of editor background
straight over the tab strip *above* it. The old code did the same thing and got
away with it because it was a document view inside a clip view. The fix is
`dirtyRect.intersection(bounds).fill()`.

The way to find it in ten minutes rather than an hour: fill with `NSColor.red`
and look at what turns red. It was the strip, exactly, and the pane's own foot.

## Pictures

Before, all of them 1400 × 900 on a 2× screen:

- `before-01-screenshot-fitted.png` — `2560 × 1600 · 42%`, the whole picture.
- `before-02-screenshot-actual-cropped.png` — the double-click's "1:1". The
  middle of the screenshot, no edges, no scrollers, and `--image-pan 1,1` moved
  it nowhere: `document=1099x789 visible=1099x789`.
- `before-03-icon-fitted.png`, `before-04-svg-actual.png` — the two small cases.
- `before-05-screenshot-zoom-2-shrinks-it.png` — ⌘+ twice over, and the picture
  went from 42% to **40%**, because the only thing the zoom reached was the
  furniture around it.

After:

- `after-01-screenshot-fitted.png` — `2560 × 1600 · Fit · 83%`. Same size on
  screen as before-01; honest number.
- `after-02-screenshot-actual.png` — 100%, `document=1312x832` against
  `visible=1084x741`, both scrollers live.
- `after-03-screenshot-actual-panned-to-the-corner.png` — the bottom right corner
  of the picture, its own edges and the checkerboard beyond them. This is the
  pair to before-02.
- `after-04-screenshot-200-percent.png` — 200%, one-pixel detail as pixels.
- `after-05-icon-actual.png`, `after-06-svg-200-percent.png` — the small cases;
  the SVG at 200% has no blur at all.
- `after-07-screenshot-fit-at-zoom-2.png` — ⌘+ twice over is now `Fit · 158%`,
  larger than the pane and scrollable, against before-05's 40%.
- `icon-interpolation-before-and-after.png`,
  `interpolation-none-against-smooth.png` — the two decisions, side by side.

## Steps

- [x] The document view is the size of the *scaled picture*, so both scrollers do
      something, and a picture larger than the pane can be panned to its edges
- [x] Zoom in and out by the decided gesture, bounded by `ImageFit.clamp`
- [x] A way back to fitting the pane, and the caption says which state it is in
- [x] `widthScale` is reused rather than a third copy of the arithmetic written,
      or there is a written reason why a picture differs from a PDF and a diagram
- [x] Double-click still does something sensible and is written down
- [x] Checked on a large screenshot, a 16-pixel icon and an SVG
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] `spec/previews.md` says what the project now does
