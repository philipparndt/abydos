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
       A model that would not render shows no model
       A picture opens whole and can be looked at closely
-->

## MODIFIED Requirement: A picture opens whole and can be looked at closely

A picture opens fitted to the pane, the whole of it, and never blown up past the
size the file says it is: a sixteen-pixel icon filling the window would be a
blurry lie about what is in it. Under it the pane says what the file holds in
pixels, how large it is being drawn, and which of the two ways it got there —
`Fit · 83%` while it is following the pane, and `200%` when somebody has chosen
a size.

Fitted is where a picture *starts*. **⌘+ and ⌘- make the picture larger and
smaller and leave the rest of the window alone**, and so does a pinch over it.
That is the one place in this program where the zoom keys do not mean the
interface: a picture is not furniture around the content, it *is* the content,
and enlarging it is looking closer at the file — the same act the editor's text
zoom performs on text. So the keys mean the picture while a picture pane has the
keyboard, and mean the window everywhere else, including in the source half of a
split showing an SVG. A right-click over the picture says which four sizes are
on offer: `Zoom In`, `Zoom Out`, `Actual Size` and `Fit to Window`. A
double-click swaps between the fit and the picture's own size, which is the
question a scaled-down screenshot always raises.

The sizes ⌘+ stops at are the size the picture is **drawn** at — 10%, 25%, 50%,
75%, 100%, 150%, 200%, 300%, 400%, 600%, 800% — so a fitted screenshot at 41%
goes to 50% and then to 75%, and "press ⌘+ until it says 400%" is the same
number of presses whatever shape the window is. A pinch is continuous and stops
where the fingers stop; the next ⌘+ takes the rung above wherever that was.

**A size somebody chose is that size, whatever the interface is zoomed to.**
`Actual Size` means 100% — one point of the file on one point of the screen —
at a 1× interface and at a 2× one alike, and it does not put the window's zoom
back to 1× to get there. The *fit* is the other half and still follows the
interface, the way every other pane's contents do: a window somebody has zoomed
to 150% opens a picture 150% larger than the pane alone would.

A picture's own scale is not remembered anywhere. It lives as long as the tab
does, because a picture opens fitted — which is the answer to "what is in this
file" — and a scale is a way of looking at this one picture for a moment. The
interface's zoom is the part that is remembered, because that is the part
somebody sets once for their eyesight or their screen.

**Anything larger than the pane is scrolled, not cropped.** That is what makes
zooming in mean anything: past the fit there is somewhere to go, both scrollers
reach the picture's own edges, and the zoom is bounded only where the arithmetic
stops being sensible — a tenth, and eight times over. A zoom keeps the middle of
the pane on the same part of the picture, whether it came from a key or from a
pinch, because a zoom that puts somebody back at the top left of what they were
reading is a zoom they have to undo by hand.

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

The PDF and diagram panes do not work this way: ⌘+ over either of them is still
the interface's zoom, which theirs multiplies. That is a difference somebody
would notice and it is deliberate — a picture is the only one of the three that
was reported as wrong, and whether a page and a drawing should follow is a
question put to the reporter and not yet answered.

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

### Scenario: the rest of the window while a picture is zoomed

- **Given** a picture fitted in a window at its ordinary size
- **When** ⌘+ is pressed twice over the picture
- **Then** the picture is drawn larger and the editor's font, the tree's rows and
  the tab strip are exactly the size they were

### Scenario: a picture in a window somebody has zoomed

- **Given** an interface zoomed to 150%
- **When** a picture is opened and then `Actual Size` is chosen
- **Then** the fitted picture was 150% of what the pane alone would have shown,
  the chosen size is 100% and says so, and the interface is still at 150%

### Scenario: a sixteen-pixel icon

- **Given** a 16 × 16 icon
- **When** it is opened
- **Then** it is drawn at sixteen points on a checkerboard rather than blown up
  to fill the window, and ⌘+ enlarges it from there to 800% without the window
  around it changing size

### Scenario: a pinch over a picture

- **Given** a fitted picture
- **When** two fingers open on the trackpad over it
- **Then** the picture grows with them, continuously, and nothing else in the
  window does

### Scenario: an SVG

- **Given** an SVG, which opens as its text beside the drawing
- **When** the drawing is clicked and zoomed
- **Then** it is redrawn at that size with no blur at all — and ⌘+ with the
  caret still in the source half is the interface's zoom, as it is in any other
  text
