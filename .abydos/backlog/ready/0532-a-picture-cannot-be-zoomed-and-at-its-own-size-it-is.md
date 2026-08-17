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

## Steps

- [ ] The document view is the size of the *scaled picture*, so both scrollers do
      something, and a picture larger than the pane can be panned to its edges
- [ ] Zoom in and out by the decided gesture, bounded by `ImageFit.clamp`
- [ ] A way back to fitting the pane, and the caption says which state it is in
- [ ] `widthScale` is reused rather than a third copy of the arithmetic written,
      or there is a written reason why a picture differs from a PDF and a diagram
- [ ] Double-click still does something sensible and is written down
- [ ] Checked on a large screenshot, a 16-pixel icon and an SVG
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does
