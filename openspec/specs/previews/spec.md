# Previews

## Purpose

Files whose rendered form is the point of them — Mermaid, Cadova models, go3mf recipes, pictures — shown beside or instead of their source, built only once somebody has looked, and never by writing into the project.
## Requirements
### Requirement: A file whose rendered form is the point of it opens showing both

A file whose rendered form is the point of it SHALL open showing both.

Some files are written in order to make something else: a `.puml` and a `.mmd`
are written to make a diagram, a `.scad` is written to make a shape, and so is
the Swift in a [Cadova](https://github.com/tomasf/Cadova) model. For those, the
work is checking one against the other, so both halves are on screen from the
moment the file opens and neither has to be asked for. A file that is read as
well as rendered — markdown — opens as itself, and a file with no readable
source at all — a mesh, a picture, a PDF, a draw.io document — opens rendered.

Nearly always the name decides, and where it cannot the file is not guessed at
from a distance: the one question that needs an answer is asked once, when the
file is opened, and everything afterwards is told rather than asked. A `.yaml`
is a 3D model when its head says it is a go3mf recipe. A `.swift` is a 3D model
when the package above it declares an executable target that depends on Cadova
and the file is one of that target's sources — the manifest is the only place
that says so, and neither the extension nor the contents of the file can.

**A go3mf recipe opens as its text, with the model offered rather than shown**,
which is the one place a 3D model does not follow the rule above. Two things
make it different from a `.scad`, and both are about cost rather than taste. A
recipe is an *assembly*: it names a `.scad` per part, so its model is every
part's render and then a `go3mf build` on top of them, which is the slowest
preview this program has. And whether the file is a recipe at all was decided by
reading the head of it — a default that starts that work off the back of a guess
is a default that makes opening YAML feel dangerous.

One place decides this for every feature that needs the answer, so the tab bar's
control, the View menu and the editor cannot disagree about what a file is.

#### Scenario: a go3mf recipe

- **Given** a `.yaml` whose head has a top-level `output:` and a top-level
  `objects:`
- **When** it is opened
- **Then** it opens as text, and the tab bar's control offers the model beside
  the source rather than showing it

#### Scenario: the rest of a repository's YAML

- **Given** a `.yaml` that is a CI definition, a compose file or a Helm chart
- **When** it is opened
- **Then** it opens as text and no model is offered at all

### Requirement: A preview nobody has looked at yet costs nothing

A preview nobody has looked at yet SHALL cost nothing.

Rendering a model means running something: OpenSCAD for a `.scad`, and a whole
package build for a Cadova model. It is the tab in front that is worth paying
for. So the viewer in a pane is built, and any program it needs is started, when
the pane has been on screen for long enough to mean it, and never merely because
a tab exists. Arrowing down a directory of models must not feel like the tree is
broken, and a project reopening with twenty of them must not render twenty.

#### Scenario: arrowing past a directory of models

- **Given** a project of twenty `.scad` files
- **When** the tree is walked from top to bottom without pausing
- **Then** nothing is rendered

#### Scenario: stopping on one of them

- **Given** the same walk
- **When** it pauses on a file
- **Then** that file, and only that file, is rendered

#### Scenario: twenty of them opened at once

- **Given** twenty `.scad` files opened together, from a search result or a
  restored session
- **When** the window comes up
- **Then** one model is rendered — the tab in front — and the other nineteen
  tabs wait until somebody clicks them

#### Scenario: a Cadova model in a tab that is not in front

- **Given** a Cadova model and another file opened together, with the other file
  in front
- **When** the window comes up and is left alone
- **Then** no build is started and no model is written

### Requirement: A Cadova model is built and run to be seen

A Cadova model SHALL be built and run in order to be seen.

A Cadova model is not a file the viewer can open. It is an executable target in
a Swift package, and the shape exists only once the program has been built and
run: `swift run <product>` in the package root writes a 3MF beside the package,
and that is what the model half shows.

Two things follow that nothing else in the previews needs. **Where the file is
can only be learnt from the run**, because Cadova names it after the model
inside the code rather than after the target or the file, so the pane reads the
path out of what the run printed. And **a run takes seconds and can fail**, so
the pane says what it is doing while it does it, and a build that produces no
model shows what the compiler said in place of the model rather than a shape
that is not the one the code describes.

What the pane says while it builds is the build's own last line, so it is text
of no known length: it is shown **on one line, truncated in the middle**, with
the turning indicator **above** it rather than through it. The two are one
arrangement centred in the pane, so no length of line and no width of pane can
put them on top of each other — and when nothing is turning the line is centred
on its own, rather than held at an offset that only makes sense with something
above it.

Any of the target's sources counts, not only the file with the model in it:
running the target is what makes the shape, so a helper file changes it just as
much. Which means the pane rebuilds when any of them changes **on disk** — the
compiler reads the disk, so an unsaved buffer would show the shape of the last
save — with a burst of saves producing one rebuild rather than one each, and a
change arriving during a build honoured when that build ends. A build is never
killed to make way for a newer one: a half-stopped `swift build` leaves its
build directory inconsistent, and the next build of that package is a cold one.

The file is rewritten in place, so a rebuild that writes the same path leaves
the view of the model alone — turning the part round to look at what changed is
the work, and a viewer rebuilt from nothing would put the camera back.

#### Scenario: opening one

- **Given** `Sources/spike/main.swift`, whose target depends on Cadova
- **When** it is opened
- **Then** the pane says it is building, naming the product, and shows what the
  build is saying while it runs
- **And** when the build finishes the model it wrote is shown beside the source

#### Scenario: a build line longer than the pane is wide

- **Given** a Cadova model building in a narrow pane
- **When** the build prints a line too long to fit
- **Then** the line is shown on one line with its middle elided, and the turning
  indicator is clear above it rather than drawn over the letters

#### Scenario: changing a constant

- **Given** that model on screen
- **When** a dimension in the source is changed and saved
- **Then** the target is built and run again, and the new shape replaces the old
  one without the view of it being reset

#### Scenario: a build the compiler refuses

- **Given** that model on screen
- **When** the source is saved with an error in it
- **Then** the model is taken away and the compiler's own message is shown in
  its place, naming the file, the line and what is wrong
- **And** when the source is repaired and saved, the model comes back

#### Scenario: nothing was written and nothing said `error:`

- **Given** a machine whose `swift` cannot build this package at all
- **When** the model is opened
- **Then** the pane shows what the run actually said, rather than reporting that
  no model appeared

### Requirement: Rendering a recipe does not write into the project

Rendering a recipe SHALL NOT write into the project.

A recipe names the file it produces — `output:` is not optional, and a recipe
without one is refused by the tool that reads it. So rendering one has somewhere
it wants to put a `.3mf`, and that somewhere is beside the source unless
something decides otherwise.

**Showing a file never modifies what it is showing.** The render happens in a
build directory of the viewer's own, and **the build is told to write there**:
the recipe's own `output:` is used for its file name and decides nothing else,
so the `.3mf` sitting next to the recipe — quite possibly one made by hand — is
left as it is whatever the recipe declares.

This is the sentence that changed. A recipe whose `output:` was absolute, or
climbed out with `..`, used to be refused rather than rendered, because the
working directory was the only lever the viewer had and a working directory
cannot contain an absolute path. The tool honours `-o` for a recipe from 0.16.6,
so containment is a property of the command now and there is nothing left to
refuse — **except against an older tool**, which ignores the flag and writes
where the recipe said. That case SHALL still be refused, and the refusal SHALL
say that it is the tool's age rather than a limit on what a viewer can contain.

#### Scenario: a recipe that names a file beside itself

- **Given** a recipe with `output: adapter-set.3mf`, and an `adapter-set.3mf`
  already beside it
- **When** the model is asked for
- **Then** the model is shown, and the file beside the recipe is untouched

#### Scenario: a recipe that names somewhere outside

- **Given** a recipe whose `output:` is an absolute path or begins `../`
- **When** the model is asked for
- **Then** the model is shown, and nothing is written where the recipe pointed

#### Scenario: a tool too old to be told

- **Given** a `go3mf` older than 0.16.6, which ignores `-o` for a recipe
- **When** such a recipe is asked for
- **Then** nothing is written and the viewer says the tool is too old, rather
  than writing where the recipe pointed

### Requirement: A model that would not render shows no model

A model that would not render SHALL show no model.

A render can fail: a `.scad` with an unclosed bracket, a recipe that names a part
that is not there, or a machine with no OpenSCAD on it at all. When one does,
**the pane draws nothing** — and says what went wrong, which for OpenSCAD not
being installed is the command that installs it.

Nothing is a deliberate answer rather than an absence of one. The alternative was
a lit cube on the build plate, which is what this pane used to fall back to, and
it is worse than an empty pane in the one way that matters: somebody who did not
write the file cannot tell that the shape on screen is not the shape their code
describes. A message alone does not settle it either. This pane is captured
through the viewer's Metal snapshot, which sees the scene and not the layer above
it, so in a screenshot — the docs, a bug report, an agent checking its own work —
the shape is the *only* thing that says whether the load worked. A shape that is
not the model is a lie a picture cannot correct.

The file is watched even though it never loaded, so the message is a promise the
program keeps: repair the source and the model appears where the message was.

This is the embedded viewer's own behaviour, which this project pins rather than
writes. The Cadova pane reaches the same answer from this project's own code —
the model goes and the compiler's message takes its place — and the two agree on
purpose: which half of the program draws a pane is not a thing anybody looking at
one should be able to tell from how a failure reads.

#### Scenario: a `.scad` that does not compile

- **Given** a `.scad` with a syntax error in it
- **When** it is opened
- **Then** the model half shows no shape at all, and says the render failed and
  what OpenSCAD said about it

#### Scenario: a machine with no OpenSCAD

- **Given** a `.scad` on a machine where OpenSCAD cannot be found
- **When** it is opened
- **Then** the model half shows no shape, and says OpenSCAD is not installed and
  how to install it

#### Scenario: the source is repaired

- **Given** that pane, showing nothing and saying why
- **When** the file is corrected and saved
- **Then** it is rendered again, the model appears, and the message goes

### Requirement: A picture opens whole and can be looked at closely

A picture SHALL open whole, and SHALL be able to be looked at closely.

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

#### Scenario: a screenshot larger than the pane

- **Given** a 2560 × 1600 screenshot from a Retina screen
- **When** it is opened
- **Then** the whole of it is on screen, fitted, and the pane says `2560 × 1600
  · Fit · 83%`

#### Scenario: its own size

- **Given** that screenshot fitted
- **When** it is double-clicked, or `Actual Size` is chosen
- **Then** it is drawn at the size the file says it is, one of its pixels to one
  pixel of the screen, and the part of it that does not fit is reached by
  scrolling to the picture's own edges rather than cut off at the pane's

#### Scenario: zooming in on the pixels

- **Given** a screenshot at its own size
- **When** ⌘+ is pressed until the pane says 400%
- **Then** each pixel of the file is a square of sixteen rather than a smudge,
  and the part of the picture that was in the middle of the pane is still there

#### Scenario: the rest of the window while a picture is zoomed

- **Given** a picture fitted in a window at its ordinary size
- **When** ⌘+ is pressed twice over the picture
- **Then** the picture is drawn larger and the editor's font, the tree's rows and
  the tab strip are exactly the size they were

#### Scenario: a picture in a window somebody has zoomed

- **Given** an interface zoomed to 150%
- **When** a picture is opened and then `Actual Size` is chosen
- **Then** the fitted picture was 150% of what the pane alone would have shown,
  the chosen size is 100% and says so, and the interface is still at 150%

#### Scenario: a sixteen-pixel icon

- **Given** a 16 × 16 icon
- **When** it is opened
- **Then** it is drawn at sixteen points on a checkerboard rather than blown up
  to fill the window, and ⌘+ enlarges it from there to 800% without the window
  around it changing size

#### Scenario: a pinch over a picture

- **Given** a fitted picture
- **When** two fingers open on the trackpad over it
- **Then** the picture grows with them, continuously, and nothing else in the
  window does

#### Scenario: an SVG

- **Given** an SVG, which opens as its text beside the drawing
- **When** the drawing is clicked and zoomed
- **Then** it is redrawn at that size with no blur at all — and ⌘+ with the
  caret still in the source half is the interface's zoom, as it is in any other
  text

### Requirement: A preview run is told not to reveal what it writes

The run that builds a Cadova model SHALL tell Cadova not to reveal the file it
writes.

Cadova reveals its output in the Finder when a build finishes, which is right
for somebody who ran `swift run` themselves and wrong for a pane that runs it
again on every save of any of the target's sources. The setting SHALL be made
in the environment of that run — the process this app starts — and SHALL NOT be
required of the model's own code: a model from anybody's repository has no
reason to know this app exists.

The run's environment SHALL be this process's own with that one variable added.
Replacing it would leave the run without a `PATH`, a `HOME` or anything else the
toolchain it starts needs.

The name of the variable SHALL be spelled in one place beside the command the
run is, so that a rename upstream is one line rather than a search.

#### Scenario: a model rebuilt on save

- **GIVEN** a Cadova model open in the preview
- **WHEN** one of its target's sources is saved and the pane rebuilds
- **THEN** the model is redrawn and no Finder window is opened

#### Scenario: a model that never heard of this app

- **GIVEN** a Cadova model whose code does not set `isFileRevealingEnabled`
- **WHEN** it is previewed
- **THEN** it behaves the same as one that does

#### Scenario: the run still finds its toolchain

- **GIVEN** a `swift` that a version manager owns rather than the system
- **WHEN** the preview builds
- **THEN** the run has the environment it had before, with only that variable
  added

### Requirement: A recipe is contained by the command that builds it, not by what it declares

A recipe SHALL be previewed into the build directory whatever its `output:`
says, because the build is given `-o` and the recipe's own declaration decides
nothing.

The preview used to refuse an `output:` that was absolute or climbed out with
`..`, on the grounds that the working directory was the only lever it had and a
working directory cannot contain an absolute path. That was true while `go3mf`
ignored `-o` for a YAML recipe. It stopped being true in 0.16.6, and an error
that explains itself with something untrue is worse than a terse one.

**Passing `-o` SHALL depend on the version answering for it.** Against 0.16.5 and
older the flag is ignored and the file is written somewhere else silently, which
is a worse failure than the one being fixed — so an older tool SHALL keep the
refusal.

**The export path SHALL be unaffected.** Building a recipe *into* the project and
handing the result to a slicer is a different verb with the opposite requirement,
and it reads the declared `output:` on purpose.

#### Scenario: a recipe naming an absolute path

- **GIVEN** a recipe whose `output:` is an absolute path, and a `go3mf` that
  honours `-o`
- **WHEN** it is previewed
- **THEN** it renders, and nothing is written outside the build directory

#### Scenario: a recipe climbing out

- **GIVEN** a recipe whose `output:` begins `../..`
- **THEN** the same

#### Scenario: a tool too old for the flag

- **GIVEN** a `go3mf` older than 0.16.6
- **WHEN** such a recipe is previewed
- **THEN** it is refused as it is today, rather than built somewhere unexpected

#### Scenario: exporting is not previewing

- **GIVEN** any of those recipes
- **WHEN** it is built for a slicer rather than for the viewer
- **THEN** it is written where the recipe says

### Requirement: A video opens as a player, silent until asked

A video whose container the system decodes natively (`.mp4`, `.mov`, `.m4v`)
SHALL open in the editor area as a player showing its first frame, paused,
with the system's transport controls — a tab shaped like a picture's, with no
document and no dirty state. It SHALL NOT play sound until play is pressed,
and switching away from the tab SHALL pause it. A container the system cannot
decode keeps the binary notice and its Quick Look.

The notice's own comment concedes the point — the obvious thing to do with a
video is watch it — and then hands the watching to a floating panel that
belongs to no tab and closes on a keypress.

#### Scenario: an mp4 opens paused

- **GIVEN** a screen recording `demo.mp4`
- **WHEN** it is opened
- **THEN** the tab shows its first frame and transport controls, and nothing
  is playing

#### Scenario: switching away silences it

- **GIVEN** the video playing
- **WHEN** another tab is brought to the front
- **THEN** playback pauses, and coming back does not resume it by itself

#### Scenario: a container the system cannot play

- **GIVEN** a `capture.webm`
- **WHEN** it is opened
- **THEN** the binary notice appears as it does today, Quick Look button and
  all

