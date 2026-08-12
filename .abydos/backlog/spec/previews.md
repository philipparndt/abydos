# Previews

## Requirement: A file whose rendered form is the point of it opens showing both

Some files are written in order to make something else: a `.puml` and a `.mmd` are
written to make a diagram, and a `.scad` is written to make a shape. For those, the
work is checking one against the other, so both halves are on screen from the moment
the file opens and neither has to be asked for. A file that is read as well as
rendered — markdown — opens as itself, and a file with no readable source at all — a
mesh, a picture, a PDF, a draw.io document — opens rendered.

One place decides this for every feature that needs the answer, so the tab bar's
control, the View menu and the editor cannot disagree about what a file is.

### Scenario: an OpenSCAD file

- **Given** a project containing `adapter.scad`
- **When** it is opened
- **Then** the source is on the left and the model is beside it, and the tab bar's
  control reads `Split Right`

### Scenario: a mesh, which has no source half

- **Given** `part.stl`
- **When** it is opened
- **Then** the tab is the model and nothing else, and `Source` and the two splits are
  not offered

### Scenario: markdown, which is read as well as rendered

- **Given** `notes.md`
- **When** it is opened
- **Then** it opens as text, and the preview is there to be asked for

## Requirement: A preview nobody has looked at yet costs nothing

Rendering a model means running OpenSCAD, and it is the tab in front that is worth
paying for. So the viewer in a pane is built when the pane has been on screen for
long enough to mean it, and never merely because a tab exists. Arrowing down a
directory of models must not feel like the tree is broken, and a project reopening
with twenty of them must not render twenty.

### Scenario: arrowing past a directory of models

- **Given** a project of twenty `.scad` files
- **When** the tree is walked from top to bottom without pausing
- **Then** nothing is rendered

### Scenario: stopping on one of them

- **Given** the same walk
- **When** it pauses on a file
- **Then** that file, and only that file, is rendered

### Scenario: twenty of them opened at once

- **Given** twenty `.scad` files opened together, from a search result or a restored
  session
- **When** the window comes up
- **Then** one model is rendered — the tab in front — and the other nineteen tabs
  wait until somebody clicks them

Nothing is claimed here about what the pane shows when the render *fails* — because
what it shows is a test cube and no message, which is 0484 and is not a requirement
anybody would write down. It is left out rather than described so that the spec does
not read as though somebody chose it.
