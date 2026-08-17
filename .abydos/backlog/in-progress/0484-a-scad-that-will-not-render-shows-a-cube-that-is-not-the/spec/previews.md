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

## ADDED Requirement: A model that would not render shows no model

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

## MODIFIED Requirement: A preview nobody has looked at yet costs nothing

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
