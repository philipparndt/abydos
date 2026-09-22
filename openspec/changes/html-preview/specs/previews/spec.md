## MODIFIED Requirements

### Requirement: A file whose rendered form is the point of it opens showing both

A file whose rendered form is the point of it SHALL open showing both.

Some files are written in order to make something else: a `.puml` and a `.mmd`
are written to make a diagram, a `.scad` is written to make a shape, and so is
the Swift in a [Cadova](https://github.com/tomasf/Cadova) model. For those, the
work is checking one against the other, so both halves are on screen from the
moment the file opens and neither has to be asked for. A file that is read as
well as rendered — markdown, and HTML — opens as itself, and a file with no
readable source at all — a mesh, a picture, a PDF, a draw.io document — opens
rendered.

**HTML is read as well as rendered**, so it opens as its text with the page
offered. A hand-written page passes the test above — it is written in order to
make the thing it renders to — and it is the one kind here whose name cannot be
told from a machine-written one. A coverage report and a generated API document
are HTML of several megabytes, and a default that rendered them would be paid
every time somebody opened a directory of build output. The cost of being wrong
is one click, once, and the mode is remembered thereafter.

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

#### Scenario: a page and a report

- **Given** a hand-written `docs/index.html` and a generated `coverage/index.html`
- **When** each is opened
- **Then** both open as text with all four modes offered, and neither is
  rendered until one is asked for

### Requirement: A preview nobody has looked at yet costs nothing

A preview nobody has looked at yet SHALL cost nothing.

Rendering a model means running something: OpenSCAD for a `.scad`, and a whole
package build for a Cadova model. Rendering a page means a web view and a
parse of however much markup the file holds. It is the tab in front that is
worth paying for. So the viewer in a pane is built, and any program it needs is
started, when the pane has been on screen for long enough to mean it, and never
merely because a tab exists. Arrowing down a directory of models must not feel
like the tree is broken, and a project reopening with twenty of them must not
render twenty.

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

#### Scenario: a page in a tab nobody has asked to see

- **Given** an HTML file opened as source, or one restored in a tab that is not
  in front
- **When** the window is left alone
- **Then** no web view is built and no markup is parsed
