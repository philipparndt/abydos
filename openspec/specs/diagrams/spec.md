# Diagrams

## Purpose

Mermaid diagrams, drawn by the real Mermaid in a web view and then flattened into geometry, so that the same file is the same picture in the app's own pane, in Preview.app and in a browser. Covers what is drawn, what is written out, and what a build says when it has not got the layout a diagram asks for.

## Requirements

### Requirement: A drawing is a picture everywhere, not only in a browser

A drawing SHALL be the same picture everywhere, not only in a browser.

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

#### Scenario: a diagram whose links are gradients

- **Given** a Sankey diagram, whose flows are strokes painted with a gradient
- **When** it is drawn in the pane and exported as an SVG
- **Then** the flows are in both, at the weight the browser gives them

#### Scenario: a diagram whose labels Mermaid draws twice

- **Given** a user journey, whose labels Mermaid emits as HTML in a
  `foreignObject` and again as plain text beside it
- **When** it is drawn in the pane and exported
- **Then** the labels are the plain text, in the same place and the same colour
  in both

#### Scenario: the two renderers, compared

- **Given** any of the kinds of diagram Mermaid draws
- **When** the exported SVG is rasterised by CoreSVG and the exported PNG by
  WebKit
- **Then** the two differ over less than a tenth of the page

### Requirement: A diagram that asks for a layout this build has not got says so

A diagram that asks for a layout this build has not got SHALL say so.

Mermaid's own layout is part of the bundle in the app; the others are separate
packages, and none is shipped. Asked for one of them, Mermaid does not refuse —
it lays the diagram out its own way and says nothing, so a diagram arranged
differently from the way its author asked is the only sign.

So the app says it: one line under the drawing, in the pane and under a
Markdown fence, naming the layout that was asked for and what was drawn
instead. It is the same place, and the same kind of sentence, as the one a file
that sets its own colours gets.

#### Scenario: a flowchart asking for ELK

- **Given** a diagram whose front matter says `layout: elk`
- **When** it is previewed
- **Then** it is drawn with Mermaid's own layout
- **And** a line under it says that "elk" is not in this build

#### Scenario: a diagram asking for the layout that is here

- **Given** a diagram whose front matter says `layout: dagre`
- **When** it is previewed
- **Then** there is no such line, because nothing was substituted

### Requirement: A pane with no diagram in it says why, and the indicator stays clear of what it says

A pane with no diagram in it SHALL say why, and the indicator SHALL stay clear of what it says.

A diagram pane is a picture or it is a sentence. There is no picture while a
tool is being run, none for a file with nothing drawable in it yet, and none for
a diagram the tool refuses — so the pane says what is happening or what is
wrong, in the middle, with the turning indicator above the message rather than
through it.

The message is **wrapped, not elided**: what it says is a sentence somebody
wrote to be read — what to install, what the parser expected and on which line —
and the middle of such a sentence is usually the part worth having. So it may be
several lines, and the two are one arrangement centred in the pane, so that no
length of message and no width of pane can put the indicator inside the text.

When nothing is turning the message is centred on its own. It is not held at an
offset that only makes sense with something above it: a pane showing a file with
nothing to draw, or a complaint about one, stays that way until somebody does
something about it, so a gap reserved for an indicator that is not there would
be on screen for the whole of the state it was reserved for.

#### Scenario: a message long enough to wrap while a tool is running

- **Given** a diagram being drawn, in a pane narrow enough that what the pane is
  saying takes more than one line
- **When** it is looked at
- **Then** the message is shown whole, over as many lines as it needs, and the
  turning indicator is clear above it rather than drawn over the letters

#### Scenario: a diagram the tool will not draw

- **Given** a file whose diagram does not parse
- **When** the tool answers
- **Then** the pane shows what it said, centred in the pane, with nothing
  turning above it and no gap where something turning would have been

#### Scenario: a picture arrives

- **Given** any of the above
- **When** a drawing is produced
- **Then** the picture replaces the message rather than being drawn over it
