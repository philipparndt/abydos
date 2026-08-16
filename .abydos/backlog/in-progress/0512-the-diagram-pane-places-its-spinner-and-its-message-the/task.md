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

## What it is now, and what it was watched doing

One `NSStackView`, vertical, centred in the pane, spacing 8, the indicator first
and the message under it. The message is an `NSTextField` label and **it goes on
wrapping** — see the decision below — with `preferredMaxLayoutWidth` and its
width constraint both set from `pane − 64` in `layout()`, which is the width the
drawn message had.

Measured in the running app, from the two views' own frames rather than from a
sum that agrees with the drawing by hand:

    448 × 667 pane, mid-render, a four-line message
      notice=30,292 388x60   spinner=216,360 16x16
      → 8 points of clear air; block 292…376, centred on the pane's 333.5

    448 × 693 pane, mid-render, one line
      notice=30,327 388x15   spinner=216,350 16x16
      → 8 points again

    448 × 667 pane, PlantUML's hint at three lines, nothing turning
      notice=30,311 388x45   spinner=none
      → 311…356, centred on 333.5 on its own, with no hole above it

    228 × 653 pane, a four-line Mermaid fault, nothing turning
      notice=30,297 168x60   spinner=none

    a picture
      state=picture  notice=none  spinner=none

Eight points at every width and every height, because eight points is the
stack's spacing. `notice=` starts at x 30 rather than the drawn message's 32
because an `NSTextField`'s frame is two points wider than its alignment rect on
each side; the constraint is on the alignment rect, so the text is where it
always was.

`0512-after-drawing.png` is a pane mid-render with a long message,
`0512-after-short.png` one with a short one, `0512-after-waiting.png` the
PlantUML hint with nothing turning and `0512-after-narrow.png` a four-line fault
in a 228-point pane. The `-crop` files are the pane itself out of each, and
`0512-before-crop.png` is the same pane before, with the spokes between the "to"
and the "draw".

**The long message mid-render had to be staged, and that is worth knowing.** The
only messages this pane shows for more than a moment *with something turning*
are PlantUML's `Drawing with …`, and PlantUML is not on this machine — Mermaid's
own render is fifteen thousandths of a second and its notice at that moment is
the one-line "Nothing to draw yet.". So the photograph is of a `plantuml` on the
PATH that reads its input and sleeps: the pane names the tool it is drawing with
by path, the path is long, and the message therefore wraps to four lines for as
long as the sleep lasts. Nothing under test was touched to get it — the fake
tool is on the PATH of that one launch and nowhere else — and the driver line
beside it is the measurement the photograph illustrates.

## Two decisions, and both go against a comment that was in this file

### The message re-centres when nothing is turning

The comment at `:513` argued the other way: the message sits in the same spot
whether or not one is turning, "so it does not jump when the drawing finishes".
That is rejected, and not by inheritance from 0511 — 0511's reason was that the
Cadova pane's lone notice is over before the first frame, which is the opposite
of the case here. Three things:

- **It cannot keep the promise.** When a render ends the message either goes
  away entirely, replaced by the picture, or is *replaced by different text* —
  `Drawing with …` on one line becomes a compiler's complaint on three or four.
  Because the message wraps, that is a block of a different height, so the text
  moves whatever the anchor does. The fixed offset buys nothing at the only
  moment it was for.
- **What it costs is this pane's ordinary state, not a flicker.** Three of the
  four readings above are a message with nothing turning: an empty `.mmd` says
  "Nothing to draw yet.", a diagram half typed says what Mermaid expected, a
  machine with no PlantUML says what to install, and each of those stays until
  somebody does something about it. 0511 had to hold the Cadova pane's
  equivalent still with a six-second knob to photograph it at all. A reserved
  sixteen-point hole would be in every frame of the state it was reserved for.
- **Wrapping makes the reserved gap worse rather than neutral.** The message's
  centre was pinned at `H/2 + 12` whatever its height, so a taller message grew
  *up* into the gap rather than away from it. Keeping it put is precisely what
  put a four-line complaint through the indicator's place.

### The message goes on wrapping, where 0511's truncates

0511 made the Cadova notice one line, `.byTruncatingMiddle`. That was decided on
what *that* notice is — the last line `swift build` printed, arbitrary text that
changes several times a second, where a block changing height would move itself
and the spinner above it as the build talked, and where both ends of
`Working copy of https://…/Apus.git resolved at 0.1.4` are the interesting part.

None of that is true here. This pane's messages are sentences somebody wrote to
be read, set once per state rather than once per line of output:

    Nothing to draw yet — a diagram starts with @startuml.
    PlantUML is not installed. Either `brew install plantuml`, or name an image
      in .abydos/tools.json — {"plantuml": "plantuml/plantuml"} — and it will be
      drawn in a container instead.
    broken.mmd line 3: Expecting 'TAGEND', 'STR', 'MD_STR', … or 3 others, got
      'SUBROUTINESTART'

Eliding the middle of any of those throws away the part worth showing — the
install hint's middle *is* the command to type and the file to write. So the
answer is not to forbid the block from growing but to build an arrangement that
holds one that does, which is what a stack does and what two constants could
not. The fault was never the wrap; the wrap only made an existing collision
deeper.

## Ruled out, and other things found on the way

- **Copying 0511's answer whole.** Two thirds of it carries and the last third
  does not: the truncation is wrong here (above), the "read the theme once at
  `init`" is wrong here (below), and only the stack itself transfers unchanged.
- **Reading the theme once, when the label is built**, which is what
  `CadovaPreviewView` does. It would be a regression in this pane and not in
  that one. `draw(_:)` read `Theme.current` on every repaint, and this pane
  *listens* for `.abydosSettingsChanged` on purpose — a diagram follows ⌘+ and a
  palette change while it is open, which is 0423's lesson written into this
  file already. The Cadova pane has never followed a theme without being
  rebuilt, because its background is handed to `ColoredView` at `init`. So
  `settingsChanged` restyles the label, and it was watched doing it: the
  message is 15 points tall at 1×, 16 at one step of ⌘+, and dark on white a
  second after the appearance is switched to light.
- **`isDisplayedWhenStopped` doing the hiding.** The trap 0511 wrote down, and
  it bit here in a way 0511 did not see: it is not enough to hide the indicator
  when something *stops*, because this pane has a state in which nothing ever
  started. A `.puml` on a machine with no PlantUML sets the install hint in
  `init` and never renders, so `spin` was never called and the indicator sat in
  the stack, stopped and invisible, holding 24 points open above the message —
  measured as `notice=30,299 388x45 spinner=216,352`, the message 22 points
  below the centre it should have been on. `spin(false)` at the end of `init`
  is the fix and the report is what caught it.
- **Changing the two numbers.** The same argument 0511 made and it is stronger
  here: whatever pair keeps a 16-point indicator clear of a message would have
  to be tuned for one number of lines, and this message's line count is a
  function of the pane's width, the app's zoom and what the tool said. The
  measurements above run from one line to seventeen.
- **A cap on how many lines the message may take.** Considered, because the
  caption at the foot has one — `min(3, captionLines)` — and rejected: the
  caption shares its line with the picture and the readout, where the message
  *is* the pane's whole content at that moment, and a compiler's complaint cut
  off after three lines is the fault 0507 was. It is unbounded now, as the
  drawn message was.
- **Whether the stack should be centred in the pane less its foot.** No: the
  drawn message was centred on the whole of `bounds`, the foot is about
  eighteen points, and moving the message nine points up to match a caption
  that is usually absent would be a change nobody asked for inside a change
  about where the message is.
- **`positioned: .below, relativeTo: spinner`.** 0511's other trap, and there is
  no such call in any of these four panes — `DrawioPreviewView` adds its web
  view with a plain `addSubview`, so it is above the stack exactly as it was
  above the bare spinner. Checked rather than assumed, and it is above the
  *message* now too, which the drawn one was not: `draw(_:)` paints behind every
  subview. It cannot matter — draw.io's notice is cleared in `editorIsReady`
  before the web view is unhidden, and `onTrouble` only speaks while it is
  hidden — and it was watched: `Opening draw.io…` centred with `spinner=none`,
  then `state=nothing`.
- **A unit test.** There is still no test target for `AbydosApp`, so the
  instrument is the driver line, as it was in 0511. `--diagram-watch` prints
  both rectangles in the pane's own coordinates: the unfixed pane would have
  printed `notice=32,318 744x15 spinner=396,324 16x16`, and those two overlap.
- **`make test` is not clean, and not because of this.**
  `CadovaExampleLiveTests.runsAndWritesAThreeMF` fails on a stray `-` typed into
  `abydos-examples/cadova-models/Sources/coaster/main.swift` — `C-ircle` where
  the file says `Circle` — modified at 21:22, before this item's first launch,
  in a checkout this branch does not touch. Left alone rather than reverted:
  somebody may be exercising the "a build the compiler refuses" scenario with
  it right now, and taking another agent's file out from under them costs more
  than a red live test that has a written explanation.
  `ToolInventoryLiveTests.measuresThisVeryProcessOutOfPs` failed in the same run
  and passes alone in 0.1 s — it reads this process out of `ps` and the suite
  was at four agents' worth of load.

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
- [x] Watched, with a screenshot of a diagram pane mid-render
- [ ] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] The spec, if this changes what the project does — `spec/diagrams.md`, an
      ADDED requirement: the capability had two requirements about what a
      drawing *is* and nothing about what the pane says when there is not one

## Estimate

2026-08-16 22:06 — about half an hour left
