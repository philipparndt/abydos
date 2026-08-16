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

One place decides this for every feature that needs the answer, so the tab bar's
control, the View menu and the editor cannot disagree about what a file is.

### Scenario: an OpenSCAD file

- **Given** a project containing `adapter.scad`
- **When** it is opened
- **Then** the source is on the left and the model is beside it, and the tab
  bar's control reads `Split Right`

### Scenario: a Swift file that is a Cadova model

- **Given** a package whose manifest declares
  `.executableTarget(name: "spike", dependencies: ["Cadova"])`
- **When** `Sources/spike/main.swift` is opened
- **Then** the source is on the left and the model is beside it

### Scenario: a Swift file that is not

- **Given** the same package
- **When** its `Package.swift` is opened, or a file of a target that does not
  depend on Cadova, or any `.swift` in a project with no Cadova in it
- **Then** it opens as text, with no model half and no build

### Scenario: a mesh, which has no source half

- **Given** `part.stl`
- **When** it is opened
- **Then** the tab is the model and nothing else, and `Source` and the two
  splits are not offered

### Scenario: markdown, which is read as well as rendered

- **Given** `notes.md`
- **When** it is opened
- **Then** it opens as text, and the preview is there to be asked for

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

Nothing is claimed here about what a `.scad` pane shows when the render *fails*
— because what it shows is a test cube and no message, which is 0484 and is not
a requirement anybody would write down. It is left out rather than described so
that the spec does not read as though somebody chose it. A Cadova pane is a
different matter and does have a requirement for it, above: that pane is this
program's own, where the `.scad` one belongs to the viewer it embeds.

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
