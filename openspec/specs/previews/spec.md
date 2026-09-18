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
of no known length: it is shown **on one line, truncated in the middle**,
centred in the pane on its own. What turns while it builds is the waiting
strip every pane has, at the pane's top edge — a preview has no header to sit
under — so no length of line and no width of pane can put the two on top of
each other. A rebuild over a model still on screen shows the strip alone: the
model stays, and the build's chatter is not drawn over it.

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
  build is saying while it runs, with the strip sweeping at the top edge
- **And** when the build finishes the model it wrote is shown beside the source
  and the strip is gone

#### Scenario: a build line longer than the pane is wide

- **Given** a Cadova model building in a narrow pane
- **When** the build prints a line too long to fit
- **Then** the line is shown on one line with its middle elided, and the strip
  is at the top edge, clear of the letters

#### Scenario: changing a constant

- **Given** that model on screen
- **When** a dimension in the source is changed and saved
- **Then** the target is built and run again with the strip sweeping over the
  model that is still on screen and no line drawn over it, and the new shape
  replaces the old one without the view of it being reset

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

A video SHALL open as a player when its container is one the system decodes
natively (`.mp4`, `.mov`, `.m4v`): in the editor area, showing its first frame, paused,
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

### Requirement: An audio file opens as a player with its wave and its spectrum

An audio file SHALL open in the editor area as a player, paused at the start,
with no document and no dirty state, when its container is one the system
decodes natively (`.wav`, `.mp3`, `.m4a`, `.aac`, `.aif`, `.aiff`, `.flac`,
`.caf`). A container the system cannot decode SHALL keep the binary notice and
its Quick Look. The tab SHALL show the file's
waveform — one lane per channel for mono and stereo — and a spectrogram of the
whole file, selectable as the wave, the spectrum, or both, sharing one
playhead. It SHALL NOT play until play is pressed or Space is typed. It SHALL
keep playing when another tab is brought to the front, SHALL stop when its tab
or window is closed, and its tab SHALL show that it is playing. A loop button
SHALL play the file repeatedly with no gap added at the seam. The wave and the
spectrogram SHALL zoom and scroll together, and zoomed in SHALL be read again
at the detail the width allows. A click or drag on the drawing SHALL move the
playhead to the moment under the pointer. Starting a sound or a video SHALL pause any other that is playing, in any tab
or window. In the sound's tab, ← and → SHALL move the
playhead five seconds back or forward, and with ⇧ one second, wrapping round
while looping and stopping at the ends otherwise. Space on a sound's or a video's row
in the project tree SHALL play or pause its tab rather than open Quick Look,
and Quick Look SHALL NOT be offered for a file whose tab already shows it — a
picture, a PDF, a sound or a video. Decoding and analysis SHALL run off the main thread, begin
only when the tab is first shown, and show the waiting strip until they land;
play SHALL work before they do. A file that cannot be decoded SHALL show what
the decoder said in place of the drawing.

Asked for 2026-09-13: sound files opened as the binary notice, while video
already played in a tab.

#### Scenario: a wav opens paused, drawn

- **GIVEN** a stereo recording `take.wav`
- **WHEN** it is opened
- **THEN** the tab shows two lanes of waveform and a playhead at the start,
  and nothing is playing

#### Scenario: seeking on the wave

- **GIVEN** `take.wav` open and paused
- **WHEN** the wave is clicked halfway across
- **THEN** the playhead moves to half the duration, and pressing play starts
  from there

#### Scenario: the spectrum

- **GIVEN** a file holding a 1 kHz tone
- **WHEN** the tab is switched to the spectrum
- **THEN** the loudest band is drawn at 1 kHz on the frequency axis, and the
  playhead is at the same moment it was over the wave

#### Scenario: leaving the tab

- **GIVEN** an `.mp3` playing
- **WHEN** another tab is brought to the front
- **THEN** it keeps playing, and its tab shows a speaker

#### Scenario: closing the tab

- **GIVEN** an `.mp3` playing in a tab that is not in front
- **WHEN** that tab is closed
- **THEN** the sound stops

#### Scenario: one at a time

- **GIVEN** `take.wav` playing in a tab that is not in front
- **WHEN** `clip.mp4` is played
- **THEN** `take.wav` pauses where it was, and its tab stops showing the speaker

#### Scenario: jumping with the arrow keys

- **GIVEN** an eight-second loop in its tab with the playhead at 6 s
- **WHEN** → is pressed with the loop off, and again with it on
- **THEN** the playhead stops at 8 s the first time, and wraps to 3 s the second

#### Scenario: Space on the row

- **GIVEN** `take.wav` selected in the project tree, with the keyboard there
- **WHEN** Space is pressed, and pressed again
- **THEN** its tab plays and then pauses, and no Quick Look panel opens; a
  video's row does the same

#### Scenario: a seamless loop

- **GIVEN** a two-second drum loop with the loop button on
- **WHEN** it plays past the end
- **THEN** it carries on from the start with no gap, and the playhead wraps

#### Scenario: zooming in on a moment

- **GIVEN** a ten-minute recording
- **WHEN** the timeline is zoomed to the second between 2:00 and 2:01
- **THEN** the wave and the spectrum show that second, read again at the
  width's detail, and scrolling moves along the recording from there

#### Scenario: a long recording

- **GIVEN** an hour-long `.mp3`
- **WHEN** it is opened
- **THEN** the window stays responsive, play works at once, and the wave and
  then the spectrum arrive under the waiting strip

#### Scenario: every natively decoded container

- **GIVEN** the same tone saved as `.wav`, `.mp3`, `.m4a`, `.aac`, `.aiff`,
  `.flac` and `.caf`
- **WHEN** each is opened
- **THEN** each opens as the player with its wave, and their durations agree
  to within the encoder's padding

#### Scenario: a container the system cannot play

- **GIVEN** a `voice.ogg`
- **WHEN** it is opened
- **THEN** the binary notice appears as it does today, Quick Look button and
  all

#### Scenario: a file that is not what its name says

- **GIVEN** a `broken.wav` holding text
- **WHEN** it is opened
- **THEN** the tab says the file could not be decoded, in the decoder's words,
  and draws no wave

### Requirement: A sound file is cut to a selection

In a sound file's tab, `i` SHALL set the selection's in-point and `o` its
out-point at the playhead, in either order, and Escape SHALL clear it. The
selection SHALL be drawn across the wave and the spectrum. *Keep Selection*
(`k`) SHALL leave only the selected frames and *Delete Selection* (`⌫`)
SHALL remove them and join the frames either side; both SHALL be exact to
the frame and SHALL add no fades. A cut SHALL NOT write the file: the tab
SHALL show that it has unsaved changes, ⌘Z and ⇧⌘Z SHALL undo and redo cuts,
closing the tab SHALL ask whether to save, and ⌘S SHALL write the file in its
own format by replacing it whole. A file in a format macOS cannot encode SHALL
keep its edit and say why it was not saved.

The pane SHALL also write a selection to a file of its own, in the format the
source is in and the container the name asks for, leaving the file being played
unchanged; it SHALL offer a name carrying where in the source the selection
starts. A second `i` SHALL move the start to where the selection ended and drop
the end, and a second `o` SHALL move the end to where it began and drop the
start, so one selection carries on from the last.

Asked for 2026-09-14; writing a selection and carrying one on, 2026-09-16.

#### Scenario: a recording is cut into samples one after another

- **GIVEN** a long take with a selection between 0:12 and 0:14
- **WHEN** *Save Selection As…* writes it, `i` is pressed twice, the playhead
  runs on and `o` marks 0:19
- **THEN** the first file holds 0:12 to 0:14 and is named for 0:12, the take on
  disk is unchanged, and the selection is now 0:14 to 0:19

#### Scenario: keeping two bars of a take

- **GIVEN** an eight-second `take.wav` with the playhead at 2 s
- **WHEN** `i` is pressed, the playhead moved to 4 s, `o` pressed, and `k`
- **THEN** the tab plays a two-second file, shows the edited dot, and
  `take.wav` on disk is still eight seconds

#### Scenario: deleting a cough

- **GIVEN** the same take with 3 s to 3.5 s selected
- **WHEN** `⌫` is pressed and then ⌘S
- **THEN** `take.wav` is 7.5 s long, its frames after 3 s are the frames that
  were after 3.5 s, and the dot is gone

#### Scenario: undo

- **GIVEN** a cut not yet saved
- **WHEN** ⌘Z is pressed
- **THEN** the tab plays the file as it was, and shows no edit

#### Scenario: an MP3

- **GIVEN** `song.mp3` with a selection deleted
- **WHEN** ⌘S is pressed
- **THEN** the file is not written, the edit is kept, and the tab says macOS
  cannot write MP3

### Requirement: A song's files are edited in the song's own tab

A tab showing a song SHALL show any of the files that song is made of, in
place: the text in front SHALL change and the song's pane SHALL NOT — it SHALL
go on playing and rendering what it was, without being asked again which song
anything belongs to. Each file SHALL keep its own caret, folds, scroll and
undo across such a change. Opening one of a song's files SHALL show it in that
song's tab rather than opening another tab, whether it is opened from the
project tree, by following a definition, or by a driven step. Moving between a
song's files SHALL be recorded as navigation, so the history walks back through
it. A file no open song is made of SHALL open as itself, as any file does.

Above the text a song's tab SHALL say which of the song's files is in front:
the song's name, a menu of every file the song is made of with the one in front
marked, and the path to it. Choosing a file from that menu SHALL show it. A tab
that is not a song's SHALL show no such row.

Asked for 2026-09-16.

#### Scenario: walking into a song's files while it plays

- **GIVEN** the drive example playing, rendered once
- **WHEN** `drums.song` and then `parts/bass.song` are opened, and then the song
- **THEN** there is one tab throughout, the pane never stops and never renders
  again, the playhead only moves forward, and the row above the text names the
  song with the file in front beside it

#### Scenario: a file no song claims

- **GIVEN** a file of patterns that no open song includes
- **WHEN** it is opened
- **THEN** it opens as its own tab, and nothing asks which song it belongs to

### Requirement: A jump that finds nothing says so

Following a definition that the language server answers nothing for SHALL say
so, rather than leaving the editor where it was with no sign that anything was
asked.

Asked for 2026-09-16, of a server that answered every name asked of it and
nothing for the keyword beside them: "it seems not be possible to navigate to
includes and functions - do we miss a navigation feature in the LSP?"

#### Scenario: nothing under the caret

- **GIVEN** the caret on a word the server has no definition for
- **WHEN** a definition is asked for
- **THEN** the editor says no definition was found, and stays where it is

### Requirement: A song opens with its sound beside it

A musik-as-text `.song` SHALL open showing its text and, beside it, the sound
`mat` renders from it — the `.scad` case with sound for a shape. The pane SHALL
render with `mat render --stems` when it is first looked at and again whenever
the file changes on disk, into a directory of its own under the temporary
directory, and SHALL NOT write into the project. It SHALL show the song as one
lane — the mix — or as one lane per layer, chosen by a switch; in the stems
view each lane SHALL be named, SHALL list the tracks rendered into it, and
SHALL have a switch that silences it for playback at once without losing the
place. With the caret in a `track` block the pane SHALL light that track's
lane; in a `pattern` block, every lane whose track plays the pattern; and
clicking a lane's name SHALL put the caret on its `track` line. A new render
SHALL take over at the playhead the old one was at, playing if it was
playing. A render that fails SHALL keep the last sound playing and show the
first error over it, and clicking it SHALL reveal the line `mat` named; a pane
that never had a sound SHALL show the failure in place of the drawing. The
lanes SHALL carry the bar grid and the song's sections, and the clock SHALL
say the bar. The pane SHALL play and pause, loop, seek, zoom and scroll as the
sound tab does, and SHALL say in words when `mat` is not installed. Stems SHALL
start on the same sample, and playing every stem together SHALL sound like
playing the mix — with a `mat` that writes them through the master, as they
were written, and with an older one turned down to the limiter's ceiling. The pane SHALL export the mix, or the mix and its
stems, as WAV, FLAC or M4A beside the song, SHALL ask before replacing a file
that is there, and SHALL NOT offer a format the installed `mat` cannot write.

Asked for 2026-09-13; export 2026-09-14.

#### Scenario: a song opens rendered

- **GIVEN** `neon.song` in a project, with `mat` installed
- **WHEN** it is opened
- **THEN** the text is on the left, the pane on the right renders it and shows
  the mix's wave and spectrum, paused at the start, with the tempo and the
  number of stems in its strip

#### Scenario: the stems, and one switched off

- **GIVEN** the pane on `drunken-sailor.song`, switched to *Stems*
- **WHEN** the drums lane's switch is clicked while playing
- **THEN** five named lanes are shown, the drums are no longer heard, the
  other four play on from where they were, and the lane is drawn as off

#### Scenario: the caret lights the stem

- **GIVEN** the stems view
- **WHEN** the caret is moved into `track pad`, and then into `pattern verse`
- **THEN** the `pad` lane is lit, and then every lane whose track plays
  `verse`

#### Scenario: a lane's name goes to the source

- **GIVEN** the stems view
- **WHEN** the `drums` lane's name is clicked
- **THEN** the caret is on the `track drums` line and the lane is lit

#### Scenario: a save while playing

- **GIVEN** the song playing at bar 12
- **WHEN** a note is changed and the file saved
- **THEN** the pane renders again, and the new render plays from bar 12

#### Scenario: a save that does not parse

- **GIVEN** the song playing
- **WHEN** an instrument's name is misspelt and the file saved
- **THEN** the sound keeps playing, a strip over it says
  `unknown instrument …` with the line, and clicking the strip puts the caret
  on that line

#### Scenario: no mat

- **GIVEN** a machine without `mat` on the login shell's PATH
- **WHEN** a `.song` is opened
- **THEN** the pane says `mat is not installed` with the `cargo install` line,
  and nothing is run

#### Scenario: exporting the song with its stems as FLAC

- **GIVEN** `neon.song` open in the pane, with a `mat` that writes FLAC
- **WHEN** *Mix and Stems as FLAC* is chosen from Export
- **THEN** `neon.flac` is written beside the song and a FLAC per layer into
  `neon stems/`, and a toast offers to reveal the file

#### Scenario: an older mat

- **GIVEN** a `mat` whose `render --help` names no `--bitrate`
- **WHEN** the Export menu is opened
- **THEN** only the WAV items can be chosen

### Requirement: A playing song is debugged as a program

Playing a song SHALL open the debugger on it unless another program is being
debugged: its heard tracks SHALL be the threads, named for what each plays; a
thread's stack SHALL be the note it is on, the pattern and pass, the `play` step
and the track, each at its line; and the debugger's continue, pause, step and
stop SHALL play, pause, move to the next bar and end. While the song plays the
threads and the shown stack SHALL follow it, and a breakpoint the song stops on
SHALL be a stop of the thread that hears the line.

Asked for 2026-09-15.

#### Scenario: stopped on a pattern's line

- **GIVEN** a breakpoint on the first line of `pattern verse`, played by `track melody`
- **WHEN** the song plays to it
- **THEN** the debugger is stopped on that line with thread `melody · verse`
  selected and the stack `verse: A4:q`, `pattern verse · pass 1 of 1`,
  `play verse`, `track melody`

### Requirement: The debugger's Stack is a tree of every thread

The debug pane SHALL show every thread at the root of its Stack, under a group
when several threads share one, with each thread's frames under it — nested
when the adapter names each frame's parent, as a list otherwise — and SHALL
open the thread being shown and the threads its adapter says are busy. For a
song, a pattern's lines SHALL be side by side inside the pattern, a line with no
note sounding shown dimmed with its last note.

Asked for 2026-09-15.

#### Scenario: a breakpoint while four tracks play

- **GIVEN** the shanty stopped on the first line of `pattern verse`
- **WHEN** the Stack is shown
- **THEN** every playing track is open to its pattern's lines, the resting one
  is shut and dimmed, and `verse: A4:q` is selected and scrolled into sight

### Requirement: A song is played while it renders

The pane SHALL render a song once and play it as it is written: with a `mat`
that streams, the mix SHALL be played from its first stretch and each stretch
written after it SHALL be played straight on from the last, without a seam and
without moving the playhead, and the stems SHALL land at the end. A render that
is still being written SHALL take over from a song that is playing only once it
has reached the playhead. A render that falls behind what is being played SHALL
leave the playhead where it is and go on when more is written, rather than
reporting the end of the song. A `mat` that does not stream SHALL still render
the whole song, which is then heard when it lands. The pane SHALL draw the mix
as it is written rather than when it lands, and SHALL lay out the whole song's
length from the first stretch when the render says what it is, dimming what has
not been rendered yet.

Asked for 2026-09-16.

#### Scenario: a cold song is heard before it has rendered

- **GIVEN** a song of 3:35 nothing has rendered, and a `mat` that streams
- **WHEN** the pane opens it and it is played
- **THEN** it is playing while `mat` is still running, with as much of the song
  as has been written, the playhead runs on unbroken as the rest arrives, and
  one render — not two — produces the whole song and its stems

### Requirement: A few bars of a song loop while it is changed

Option-clicking a line's bar in a song's gutter SHALL loop the stretch of the
song where that line is heard and play it, option-clicking the same line again
SHALL stop looping, and a render landing while it loops SHALL keep looping the
same stretch. The pane SHALL show what the loop leaves out as dimmed and say
which bars it plays.

Asked for 2026-09-16.

#### Scenario: looping a pattern's line while its sound is changed

- **GIVEN** the shanty playing, and the first line of `pattern verse`, heard at bars 5–6
- **WHEN** its bar is option-clicked, and the kit's snare is then changed and saved
- **THEN** those two bars play round and round, the clock says `loop bars 5–6`,
  and the new sound is heard on the next pass

