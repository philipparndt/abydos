# Previews

## Requirement: A file whose rendered form is the point of it opens showing both

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

### Scenario: a go3mf recipe

- **Given** a `.yaml` whose head has a top-level `output:` and a top-level
  `objects:`
- **When** it is opened
- **Then** it opens as text, and the tab bar's control offers the model beside
  the source rather than showing it

### Scenario: the rest of a repository's YAML

- **Given** a `.yaml` that is a CI definition, a compose file or a Helm chart
- **When** it is opened
- **Then** it opens as text and no model is offered at all

## Requirement: A preview nobody has looked at yet costs nothing

Rendering a model means running something: OpenSCAD for a `.scad`, and a whole
package build for a Cadova model. It is the tab in front that is worth paying
for. So the viewer in a pane is built, and any program it needs is started, when
the pane has been on screen for long enough to mean it, and never merely because
a tab exists. Arrowing down a directory of models must not feel like the tree is
broken, and a project reopening with twenty of them must not render twenty.

### Scenario: arrowing past a directory of models

- **Given** a project of twenty `.scad` files
- **When** the tree is walked from top to bottom without pausing
- **Then** nothing is rendered

### Scenario: stopping on one of them

- **Given** the same walk
- **When** it pauses on a file
- **Then** that file, and only that file, is rendered

### Scenario: twenty of them opened at once

- **Given** twenty `.scad` files opened together, from a search result or a
  restored session
- **When** the window comes up
- **Then** one model is rendered — the tab in front — and the other nineteen
  tabs wait until somebody clicks them

### Scenario: a Cadova model in a tab that is not in front

- **Given** a Cadova model and another file opened together, with the other file
  in front
- **When** the window comes up and is left alone
- **Then** no build is started and no model is written

## Requirement: A Cadova model is built and run to be seen

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

### Scenario: opening one

- **Given** `Sources/spike/main.swift`, whose target depends on Cadova
- **When** it is opened
- **Then** the pane says it is building, naming the product, and shows what the
  build is saying while it runs
- **And** when the build finishes the model it wrote is shown beside the source

### Scenario: a build line longer than the pane is wide

- **Given** a Cadova model building in a narrow pane
- **When** the build prints a line too long to fit
- **Then** the line is shown on one line with its middle elided, and the turning
  indicator is clear above it rather than drawn over the letters

### Scenario: changing a constant

- **Given** that model on screen
- **When** a dimension in the source is changed and saved
- **Then** the target is built and run again, and the new shape replaces the old
  one without the view of it being reset

### Scenario: a build the compiler refuses

- **Given** that model on screen
- **When** the source is saved with an error in it
- **Then** the model is taken away and the compiler's own message is shown in
  its place, naming the file, the line and what is wrong
- **And** when the source is repaired and saved, the model comes back

### Scenario: nothing was written and nothing said `error:`

- **Given** a machine whose `swift` cannot build this package at all
- **When** the model is opened
- **Then** the pane shows what the run actually said, rather than reporting that
  no model appeared

## Requirement: Rendering a recipe does not write into the project

A recipe names the file it produces — `output:` is not optional, and a recipe
without one is refused by the tool that reads it. So rendering one has somewhere
it wants to put a `.3mf`, and that somewhere is beside the source unless
something decides otherwise.

**Showing a file never modifies what it is showing.** The render happens in a
build directory of the viewer's own, so a recipe's `output:` lands there and the
`.3mf` sitting next to the recipe — quite possibly one made by hand — is left
as it is. A recipe whose `output:` names an absolute path, or climbs out with
`..`, has no such directory that can contain it; that recipe is not rendered
rather than rendered somewhere it was not asked to go.

### Scenario: a recipe that names a file beside itself

- **Given** a recipe with `output: adapter-set.3mf`, and an `adapter-set.3mf`
  already beside it
- **When** the model is asked for
- **Then** the model is shown, and the file beside the recipe is untouched

### Scenario: a recipe that names somewhere outside

- **Given** a recipe whose `output:` is an absolute path or begins `../`
- **When** the model is asked for
- **Then** nothing is written and the viewer says why, rather than writing where
  the recipe pointed

## Requirement: A model that would not render shows no model

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

### Scenario: a `.scad` that does not compile

- **Given** a `.scad` with a syntax error in it
- **When** it is opened
- **Then** the model half shows no shape at all, and says the render failed and
  what OpenSCAD said about it

### Scenario: a machine with no OpenSCAD

- **Given** a `.scad` on a machine where OpenSCAD cannot be found
- **When** it is opened
- **Then** the model half shows no shape, and says OpenSCAD is not installed and
  how to install it

### Scenario: the source is repaired

- **Given** that pane, showing nothing and saying why
- **When** the file is corrected and saved
- **Then** it is rendered again, the model appears, and the message goes
