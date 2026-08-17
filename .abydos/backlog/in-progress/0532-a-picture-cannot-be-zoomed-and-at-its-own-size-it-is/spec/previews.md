<!-- What this item changes about `previews`. Folded into
     .abydos/backlog/spec/previews.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A file whose rendered form is the point of it opens showing both
       A preview nobody has looked at yet costs nothing
       A Cadova model is built and run to be seen
       Rendering a recipe does not write into the project
-->

## ADDED Requirement: A picture opens whole and can be looked at closely

A picture opens fitted to the pane, the whole of it, and never blown up past the
size the file says it is: a sixteen-pixel icon filling the window would be a
blurry lie about what is in it. Under it the pane says what the file holds in
pixels, how large it is being drawn, and which of the two ways it got there —
`Fit · 83%` while it is following the pane, and `200%` when somebody has chosen
a size.

Fitted is where a picture *starts*. **⌘+ and ⌘- make it larger and smaller**, the
window's own zoom and not a second one belonging to this pane, and a right-click
says so: `Zoom In`, `Zoom Out`, `Actual Size` and `Fit to Window`, the same four
the diagram pane offers. There is no pinch: this app has one zoom, every pane
follows it, and a gesture that moved only the picture would be the one place in
the window where how large things are means something else. A double-click swaps
between the fit and the picture's own size, which is the question a scaled-down
screenshot always raises.

**Anything larger than the pane is scrolled, not cropped.** That is what makes
zooming in mean anything: past the fit there is somewhere to go, both scrollers
reach the picture's own edges, and the zoom is bounded only where the arithmetic
stops being sensible — a tenth, and eight times over. A zoom keeps the middle of
the pane on the same part of the picture, because a zoom that puts somebody back
at the top left of what they were reading is a zoom they have to undo by hand.

**100% is the size the file says it is**, which is the size in points a picture
declares — so 100% of a Retina screenshot puts one of its pixels on one pixel of
the screen, and the pixel count is said beside the percentage because the
percentage alone cannot tell anybody how much detail is in the file. Above its
own pixels a picture is drawn **without smoothing**: the reason to zoom a
screenshot to 400% is to see the pixels, and interpolation hides exactly what is
being looked for. Below them it is smoothed, because dropping every other row of
a shrinking screenshot makes text unreadable. A drawing — an SVG — is not pixels
at all: it is rendered afresh at whatever size it is asked for, and zooming one
costs it no sharpness.

A window somebody resizes re-fits a picture that is fitted, and leaves a picture
at a size somebody chose exactly as large as they chose it.

### Scenario: a screenshot larger than the pane

- **Given** a 2560 × 1600 screenshot from a Retina screen
- **When** it is opened
- **Then** the whole of it is on screen, fitted, and the pane says `2560 × 1600
  · Fit · 83%`

### Scenario: its own size

- **Given** that screenshot fitted
- **When** it is double-clicked, or `Actual Size` is chosen
- **Then** it is drawn at the size the file says it is, one of its pixels to one
  pixel of the screen, and the part of it that does not fit is reached by
  scrolling to the picture's own edges rather than cut off at the pane's

### Scenario: zooming in on the pixels

- **Given** a screenshot at its own size
- **When** ⌘+ is pressed until the pane says 400%
- **Then** each pixel of the file is a square of sixteen rather than a smudge,
  and the part of the picture that was in the middle of the pane is still there

### Scenario: a sixteen-pixel icon

- **Given** a 16 × 16 icon
- **When** it is opened
- **Then** it is drawn at sixteen points on a checkerboard rather than blown up
  to fill the window, and ⌘+ enlarges it from there

### Scenario: an SVG

- **Given** an SVG, which opens as its text beside the drawing
- **When** the drawing is zoomed
- **Then** it is redrawn at that size with no blur at all
