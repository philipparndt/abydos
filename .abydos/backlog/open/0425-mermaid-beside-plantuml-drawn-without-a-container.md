# 425. Mermaid beside PlantUML, drawn without a container

A `.mmd` file opens as text and nothing else. PlantUML has a preview pane that
follows the typing, a `⌘+` that keeps the drawing sharp, and an `Export ▸ PNG` /
`Export ▸ SVG` beside the file (0422, and the export that landed the day before
this was written). Mermaid should have exactly that: the same pane, the same
submenu in the same two places, the same rules about what may be overwritten and
what must not be written at all, and renders fast enough to redraw as somebody
types.

Same experience. Not necessarily the same machinery, and this entry is mostly
about why not.

## How Mermaid is drawn, which is the decision this turns on

Mermaid is JavaScript. There is no `mmdc` that is a small program: every
command-line Mermaid is a headless browser with `mermaid.js` loaded into it.
Three ways were considered and two were measured.

### Measured: `mermaid-cli` in a container

The direct analogue of the PlantUML path, and it reuses everything — the image
pull, the naming, the sweep, `ContainerImages.explain`. Measured on this
machine, `docker pull minlag/mermaid-cli:11.16.1` (the image the project's own
README gives; `ghcr.io/mermaid-js/mermaid-cli` has no `latest` and refused an
anonymous pull):

| | |
|---|---|
| Downloaded | **879 MB** compressed, arm64 |
| **On disk** | **2.16 GB** |
| Pull time | 33 s on a fast connection |
| Render, cold container | **1.01–1.21 s**, three runs of a six-node flowchart |

For comparison, `plantuml/plantuml` is **314 MB** on this same machine. So
Mermaid by container costs **seven times PlantUML's disk** — two gigabytes and a
sixth, per user, to draw a flowchart.

And **the trick from 0422 does not transfer.** PlantUML's image has
`--http-server` built into it, which is the whole reason a kept-warm container
takes a render from 2 s to 0.05 s. `mmdc --help` offers no server mode at all:
`-i -` and `-o -` read and write a pipe, and that is the extent of it. Keeping
one warm would mean writing a server that does not exist — a Node process, a
protocol, a health check — inside somebody else's image. So the container route
is 1 s per render, for ever, per keystroke-pause.

### Measured: a `WKWebView` with `mermaid.min.js` in the app

`mermaid@11.16.1`'s UMD bundle is a single self-contained file, **3.57 MB**,
**MIT**. Loaded into an off-screen `WKWebView` with no window attached at all
and driven through `callAsyncJavaScript`:

| | |
|---|---|
| In the app | **3.57 MB**, no download, nothing to install |
| Loading the bundle | **0.16–0.28 s**, once, for the life of the web view |
| First render | **0.111 s** |
| Every render after | **0.006–0.019 s** |

That is *faster than the warm PlantUML server* (~0.05 s), it needs no container
runtime, no daemon, no pull and no network, and it works on a machine with
nothing installed on it — which is a materially better experience than PlantUML
gets today, and the reason for the asymmetry recorded below.

`mermaid.render` throws on a diagram it cannot parse rather than drawing a
picture of the complaint, and what it throws carries `hash.loc.first_line` — so
the export can refuse and name the line, which is what 0424's export work asks
for. Measured, not assumed: `hash.line` and `hash.loc.first_line` **disagree**
(2 and 3 for the same fault), and it is `loc.first_line` that matches the line
the message itself names.

### Not measured, and rejected on shape: Kroki

One container that draws both, which would eventually be one thing to install
instead of two. It is rejected for now for two reasons and neither is about
Kroki being bad. It **replaces a working PlantUML path** that was tuned three
days ago, so it is not a small change and it is not this change. And its Mermaid
is not in the main image: Kroki farms Mermaid out to a `kroki-mermaid`
companion service which is *itself* a headless Chromium, so it buys none of the
two gigabytes back. Worth revisiting as its own entry if the number of drawing
tools ever reaches three.

## Chosen: the web view

3.57 MB against 2.16 GB, 0.015 s against 1.0 s, and nothing to install. There
was not really a competition once the pull finished — and it is also the
project owner's decision, made on a second ground the numbers say nothing
about: **draw.io is wanted next, and draw.io is a web application too.** So
this is the first user of a rendering surface rather than a one-off.

### The seam, and what it deliberately is not

`WebRenderer` owns a web view, a bundled page, a call into it with a deadline,
and the tearing down of a process nobody is using. `MermaidRenderer` supplies
the page and knows what the answers mean, and it is the only client.

**There is no registry, no protocol with one conformer, and no second
implementation**, because a second client does not exist yet and building for
one would be building for a guess.

What draw.io would want that this does not have, so the next person knows how
far the seam goes:

- **It is an editor, not a renderer.** It owns a document, takes mouse and
  keyboard events, and hands *changes* back — where this hands back a picture
  for a string. That is the large difference and it is not pretended at here.
- **It is a visible view.** This web view is off-screen on purpose and is never
  put in a window; an editor has to be the pane.
- **It is bigger and it is not one file.** draw.io's app is a tree of scripts,
  styles, images and stencils, which needs a `WKURLSchemeHandler` serving a
  bundled directory rather than one inlined `<script>`.
- **Its own file format**, `.drawio`, read and written rather than parsed once.

What it *would* reuse, unchanged: the warm-and-reap, the deadline on every
call, the refusal to navigate anywhere, and the rule that nothing is fetched.

### Nothing is fetched, and that is enforced rather than intended

The page is one document with the bundle inlined into it, loaded with **no base
URL**, and `WebRenderer` refuses any navigation that is not that document. So
the app draws with no network at all, and a diagram somebody was sent cannot
reach anywhere. Inlining is also what makes it work: a `loadHTMLString` page has
no origin, so a `<script src=…>` at a `file:` URL would be a cross-origin
request and be refused.

**What it costs, said plainly:**

- **A vendored JavaScript bundle**, which this project has a place for —
  `Sources/Grammars/` vendors five tree-sitter grammars with their `LICENSE`
  beside their sources and a line in `THIRD-PARTY-NOTICES.md`. Mermaid follows
  that: `Sources/AbydosKit/Preview/mermaid/mermaid.min.js`, its `LICENSE`
  beside it, a row in the notices. MIT, and the bundle carries the notices of
  what *it* bundles (d3, dagre-d3, khroma, dompurify, and others — all
  MIT-family) in its own trailing comment, which travels with the file.
- **An update story**, which is a person and a version number rather than a
  mechanism: `Scripts/` is where the refresh belongs, the version is pinned in
  the notices, and nothing auto-updates.
- **Rendering is asynchronous inside a web view.** That was already true of the
  PlantUML pane (a subprocess) so the pane's shape does not change, but the
  renderer is `@MainActor` where the PlantUML one is not, and a render that is
  waiting is waiting on WebKit rather than on a pipe.

### The asymmetry, since somebody will ask

**Mermaid needs no container. PlantUML does** — a JVM and Graphviz, installed or
in an image. That is a fact about the two tools rather than an inconsistency in
this app: PlantUML has no form that fits in an application bundle, and Mermaid
has no form that does not. Both draw to the same pane, export with the same
menu under the same rules, and the only place the difference shows is that a
`.mmd` file draws on a machine where nothing is installed and a `.puml` file
says what to install.

## What a `.mmd` export writes, and how it refuses

Everything 0424's export decided, applying unchanged:

- The **format asked for, not the format on screen.** The pane draws SVG
  because a drawing is sharp at any zoom; `Export ▸ PNG` rasterises through a
  canvas in the same web view at 2× and writes a PNG. This was the bug called
  out in that work and it is the reason the renderer takes a format rather than
  handing back whatever it drew last.
- **Nothing written for a diagram that does not parse**, with the line named in
  one sentence: `flow.mmd line 3: Expecting …, got 'NEWLINE'`. Mermaid's own
  message carries the whole expectation list, sometimes twenty-seven tokens
  long, so it is trimmed to a sentence somebody can read.
- **A picture nobody here drew is not overwritten.** PlantUML stamps its output
  and `DiagramExport.isDrawnByPlantUML` reads the stamp. Mermaid stamps
  nothing, so this side stamps it: a `<?abydos-mermaid?>` instruction in the
  SVG and a `tEXt` chunk in the PNG. Without that, exporting the same diagram
  twice would refuse the second time, which is the ordinary way of working.

## What `mermaid.render` hands back is not a picture, and this was most of the work

Mermaid draws for a browser. What comes out is a stylesheet with some shapes
attached, and it becomes a *drawing* only after four things, each of which was
found by looking at what landed on screen, in this order.

1. **It has no size.** `<svg width="100%" style="max-width: 282px">` is right
   for a page and wrong for a file: an SVG with no intrinsic size goes into a
   browser's default 300×150 box, and the first PNG rasterised from one came out
   **172×300** instead of 564×982. The root gets explicit `width`/`height` off
   its own `viewBox`. Pure, and tested as such.
2. **`htmlLabels` is turned off.** Mermaid's default puts labels in a
   `foreignObject` full of HTML, which a browser draws and Preview.app,
   `librsvg`, Inkscape and a `<canvas>` do not. Off, the labels are `<text>` —
   so the file is a picture everywhere and rasterising it works at all.
3. **Every style is inlined onto the element.** Everything an edge looks like,
   `fill: none` above all, lives in a descendant selector inside a `<style>`
   block. CoreSVG — the renderer behind `NSImage`, and therefore behind this
   app's own preview pane and behind Preview.app — does not apply it, and
   **every edge in the first working preview was a solid black wedge.** The
   browser's own resolved values are copied onto each element as attributes and
   the stylesheet is dropped.
4. **Arrowheads and text are baked into geometry.** `marker-end` is a reference
   to a shape a renderer is expected to place, rotate and scale; CoreSVG draws
   nothing for one, so the flowchart had no arrows on it. And `x`/`y` on a
   `tspan` are *ignored* by CoreSVG, so every label was drawn from its `<text>`
   element's own origin — above its box rather than in it. Both become geometry:
   the marker's content copied to the end of the line with the transform the
   specification describes, and each row of text promoted to a `<text>` of its
   own at the position the browser measured for it.

Two things learned the hard way in that last one, both from looking at the
result rather than from reading a specification:

- The unit is the **row**, not the word. Mermaid puts every word in a `tspan` of
  its own with the spaces between them as bare text nodes, so positioning each
  word separately drew "Orderplaced" — words right, gaps gone.
- Everything must be **measured before anything is written**, because each thing
  written moves what has not been read yet.
- **`text-anchor` has to come off everything left inside a row.** It is applied
  to a text chunk by the element the chunk *starts at* — which, once a row's
  first word is its own `tspan`, is that word rather than the row. A browser
  honours it and shifts the whole label half its own width left; CoreSVG ignores
  it and does not. That produced two different pictures from one file, and it
  was only found by rasterising the same export both ways and putting them side
  by side: the pane had "Tell the customer" centred in its box and the exported
  PNG had it hanging off the left edge of the page.

It is checked both ways round: the exported SVG rasterised by CoreSVG and the
exported PNG rasterised by WebKit are the same picture, compared side by side.
That agreement is the property worth having — it means the file is a picture
rather than a program that happens to run in one place.

What is lost, and it is small: an *animated* edge stops animating, since the
`@keyframes` went with the stylesheet. A still picture in a file was never going
to animate anyway.

## Markdown fenced blocks, and the decision about them

Most Mermaid in the wild lives in ```` ```mermaid ```` inside a Markdown file
rather than in a `.mmd`, and that is where this ought to end up.

**Deliberately not in this slice, and it is not laziness.** The `.mmd` route
needs one renderer and one pane. The Markdown route needs three things this does
not have yet: the *Markdown preview* (`MarkdownRenderer`, an `NSTextView` of an
attributed string) has no way to hold a picture that redraws itself, the export
has to answer "which of the four blocks in this file?" — with a naming rule and
a gesture that names one — and a file with four diagrams in it wants four
pictures with predictable names, which is exactly the ground `DiagramExport`
already covers for `@start` blocks and would need covering again for fences.

`mermaid-cli` already does the file-of-fences case (`-i README.md` extracts
every block), which is a decent description of the behaviour to copy when
somebody gets to it. What is here is deliberately a smaller thing that works.

## What landed

`Sources/AbydosKit/Preview/` gained four files and a vendored bundle:
`WebRenderer` (the surface), `Mermaid` (the page and the tidying, all pure),
`MermaidRenderer` (the drawing), `DiagramStamp` (signing a picture), and
`mermaid/mermaid.min.js` with its `LICENSE` and `VERSION`.
`Sources/AbydosApp/Editor/DiagramPaneView.swift` is the pane both tools now
share, with `PlantUMLPreviewView` and `MermaidPreviewView` above it — so the
menu, the white paper, the ⌘+ and the notice are one implementation rather than
two that could drift.

`DiagramFormat` replaced `PlantUML.Format` as the type both menus speak, and the
refusal to overwrite now reads "was not drawn from a diagram" rather than naming
PlantUML, since it guards both.

Verified end to end in the app on a scratch project, not only in tests: a
flowchart and a sequence diagram previewed, `Export ▸ SVG` and `Export ▸ PNG`
taken from the preview's own menu, and the written files opened and looked at.

## What is left

- **Fenced blocks in Markdown**, above. The largest missing piece by far.
- **The theme.** Both panes draw on white paper, because that is what PlantUML's
  default background is and matching it was the honest thing. Mermaid has a
  `dark` theme built in and following the editor's would be a nice thing and a
  decision about what an *export* then contains, which must not follow the
  screen.
- **ELK layout** (`@mermaid-js/layout-elk`) is a second bundle and is not here.
  A diagram asking for `layout: elk` gets Mermaid's own message about it.
- ~~**An example to work against.**~~ **Done.** `abydos-examples/mermaid/` holds
  six: `render.mmd` (flowchart), `export.mermaid` (sequence, and the other
  extension), `document.mmd` (state), `preview.mmd` (class), `project.mmd`
  (entity-relationship) and `branches.mmd` (git graph), with a README saying
  what each exercises. Six rather than two because the four faults below were
  every one of them found in a flowchart or a sequence diagram, and the other
  four diagram types are laid out by different code. All six were previewed and
  exported in both formats from the app's own menu and looked at.
  `Tests/AbydosKitTests/ExampleMermaidTests.swift` draws them all and asks each
  the same questions, the way `ExampleDevContainerTests` reads the
  devcontainers.

  It found **a fifth thing that had to be baked**, and it was in a diagram type
  nothing had drawn before: `autonumber`. Mermaid numbers a message by drawing
  a line from a point to *itself* with the badge hanging off its `marker-start`
  and the numeral written in white on top. `abydosBakeMarkers` skipped a line
  with no length as nothing to place a marker on, so the reference was left
  standing on a marker that is removed a moment later — twelve white numerals
  on white paper, in the pane and in every export, with the numbers present in
  the file and absent from the picture. Fixed, and `MermaidLiveTests` has it.

  One thing worth knowing that is Mermaid's own: a comment line that is
  **exactly `%%`**, before the diagram declaration, stops a **flowchart** being
  recognised — `Expecting 'NEWLINE', 'SPACE', 'GRAPH', got 'NODE_STRING'`,
  reported at line 1. Mermaid's own comment stripping wants at least one
  character after the `%%`. Harmless inside the body, and harmless anywhere in
  the other five diagram types. This app's `hasDiagram` counts a bare `%%` as a
  comment, so the two disagree about what a comment is; nothing here depends on
  that, and it is written down because the message names the wrong place.
- **A shot in `Scripts/screenshots.sh`.** There is no diagram in the
  documentation's pictures at all — neither PlantUML's nor this — and a preview
  pane is exactly the kind of thing a picture says better than a paragraph. It
  wants the example above first.
- **The pane draws through `NSImage`,** which is CoreSVG, which is why so much
  of the flattening above exists. It is the right dependency to have — the file
  written to disk is better for it — but if a diagram ever appears that CoreSVG
  still cannot draw, the honest answer is to show the pane a bitmap rasterised
  by the web view at the zoom being asked for, and keep the drawing for the
  file.

---

Its number is where it sits in the queue, not what it is worth doing next.
