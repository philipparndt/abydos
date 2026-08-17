<!-- What this item changes about `previews`. Folded into
     .abydos/backlog/spec/previews.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A file whose rendered form is the point of it opens showing both
       A preview nobody has looked at yet costs nothing
       A Cadova model is built and run to be seen
-->

## MODIFIED Requirement: A file whose rendered form is the point of it opens showing both

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

## ADDED Requirement: Rendering a recipe does not write into the project

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
