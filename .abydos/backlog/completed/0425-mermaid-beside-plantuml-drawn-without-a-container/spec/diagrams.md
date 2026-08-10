<!-- What this item changes about `diagrams`. Folded into
     .abydos/backlog/spec/diagrams.md by `abydos-backlog done`.

     Nothing has been said about diagrams yet, so this is all ADDED — and it
     is deliberately only what this item can vouch for. A diagram pane, three
     drawing tools, the export rules and the naming of a fence's picture are
     all real and all unspecced; the two requirements below are the ones this
     item established and checked, and the file is meant to be grown by
     whoever touches the rest.
-->

## ADDED Requirement: A drawing is a picture everywhere, not only in a browser

Mermaid is drawn by the real Mermaid, in a web view inside the app, and what it
hands back is written for a browser: a stylesheet with some shapes attached,
labels in HTML, arrowheads as references to shapes a renderer is expected to
place. Before it is shown or written it is flattened into geometry — every style
resolved onto the shape it paints, every arrowhead and every row of text put
where the browser measured it — so that the same file is the same picture in the
app's own pane, in Preview.app and in a browser.

This is not a nicety. The pane draws through `NSImage`, which is CoreSVG, and
the exported PNG is rasterised by WebKit: anything left in the file that needs a
browser draws one picture on screen and a different one in the file somebody
sends on.

### Scenario: a diagram whose links are gradients

- **Given** a Sankey diagram, whose flows are strokes painted with a gradient
- **When** it is drawn in the pane and exported as an SVG
- **Then** the flows are in both, at the weight the browser gives them

### Scenario: a diagram whose labels Mermaid draws twice

- **Given** a user journey, whose labels Mermaid emits as HTML in a
  `foreignObject` and again as plain text beside it
- **When** it is drawn in the pane and exported
- **Then** the labels are the plain text, in the same place and the same colour
  in both

### Scenario: the two renderers, compared

- **Given** any of the kinds of diagram Mermaid draws
- **When** the exported SVG is rasterised by CoreSVG and the exported PNG by
  WebKit
- **Then** the two differ over less than a tenth of the page

## ADDED Requirement: A diagram that asks for a layout this build has not got says so

Mermaid's own layout is part of the bundle in the app; the others are separate
packages, and none is shipped. Asked for one of them, Mermaid does not refuse —
it lays the diagram out its own way and says nothing, so a diagram arranged
differently from the way its author asked is the only sign.

So the app says it: one line under the drawing, in the pane and under a
Markdown fence, naming the layout that was asked for and what was drawn
instead. It is the same place, and the same kind of sentence, as the one a file
that sets its own colours gets.

### Scenario: a flowchart asking for ELK

- **Given** a diagram whose front matter says `layout: elk`
- **When** it is previewed
- **Then** it is drawn with Mermaid's own layout
- **And** a line under it says that "elk" is not in this build

### Scenario: a diagram asking for the layout that is here

- **Given** a diagram whose front matter says `layout: dagre`
- **When** it is previewed
- **Then** there is no such line, because nothing was substituted
