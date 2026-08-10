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

~~**Deliberately not in this slice, and it is not laziness.**~~ ~~**The picture
is done; the export is not.**~~ **Both are done.** Three things were named as
missing: the *Markdown preview* having no way to hold a picture that redraws
itself, which is answered below; and the two about **export** — which of the
four blocks in a file somebody means, and what four pictures out of one file are
called — which are answered under "Exporting a fence" further down.

### A fence draws where the fence is

`MarkdownFence` cuts the drawable blocks out of the document before anything
else is parsed, and `MarkdownRenderer` puts the drawing where the block was. The
cutting is first rather than merely somewhere: a sequence diagram's own lines
look like other things — a `|` row reads as a pipe table, a `#` as a heading —
so every later pass would otherwise take a bite out of the picture.

The three things that were going to be hard, and what each came to.

- **A picture arrives late, and the pane draws now.** `MarkdownDiagrams` is a
  cache between the two: `render` asks it for a fence's drawing and gets one
  synchronously or gets nothing and a request. When the drawing lands, the pane
  renders the document again — the same debounced refresh the typing already
  uses, which keeps the scroll position — and finds it in the cache that time.
  Being a *cache* rather than a queue is what stops the flicker: a re-render for
  any other reason, and there is one on every pause in the typing, hands back
  the picture already drawn instead of drawing it again. Meanwhile the block is
  one quiet line saying what is happening, so nothing jumps except once.
- **Twenty fences are twenty renders through one web view, in turn.** There is
  one `WebRenderer` in the app and the queue is drained oldest first, so a
  document fills in from the top at six to nineteen thousandths of a second
  each. The refresh being debounced is what keeps twenty renders from being
  twenty re-renders of the document.
- **A fence that does not parse shows its code and its complaint.** Never a gap
  and never a blank document: the block stays exactly as it was written and the
  sentence goes under it, with the line counted from the top of the *file*
  rather than of the block — `DiagramFault.sentence(offset:)` already took the
  offset, and the fence knows which line it opened on.

Two things it deliberately does not do. **There is no second renderer**: a fence
goes through `MermaidRenderer.shared`, which means the same page, the same
`abydosInline`, and the same five fixes for what a browser hands back — a second
path is how a fence would end up with black wedges for edges again. And **there
is no second theme rule**: a fence has no front matter unless it carries one, so
it follows the app; one with `%%{init: … theme … }%%` keeps its own and says so
in the same sentence the `.mmd` pane uses.

The drawing is an `NSTextAttachmentCell` rather than an attachment of a fixed
size, which is what makes it reflow: a cell is asked how large it wants to be
for the line fragment it is going into, so a diagram wider than the pane shrinks
to fit and grows again when the divider is dragged, with nothing watching the
frame. It is never drawn *larger* than it was laid out — a two-node flowchart
stretched to the width of the window is a picture of nothing much.

One thing found by looking at the first screenshot rather than by reasoning: a
text view's coordinates run downwards and an `NSImage` is drawn in its own, so
the short form of `NSImage.draw(in:)` put every diagram in the preview upside
down and mirrored. `respectFlipped: true` is the whole fix.

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

The fence export is `DiagramExport.fences`, `.fenced`, `.holdsADiagram` and
`.export(markdown:)` in the kit, `Mermaid.statedTitle` beside `statedLook`, and
the `Export ▸` on `MarkdownPreviewTextView` beside the one the tree already had.
`Tests/AbydosKitTests/MarkdownDiagramExportTests.swift` holds the naming rules
and `MermaidLiveTests` writes the pictures and reads them back.

Verified end to end in the app on a scratch project, not only in tests: a
flowchart and a sequence diagram previewed, `Export ▸ SVG` and `Export ▸ PNG`
taken from the preview's own menu, and the written files opened and looked at.

## What is left

- ~~**Fenced blocks in Markdown.**~~ **Drawn.** See above. `MarkdownFence` in the
  kit, `MarkdownDiagrams` and the cell beside `MarkdownRenderer`, and
  `Tests/AbydosKitTests/Fixtures/diagrams.md` and `broken-diagram.md` as the two
  documents it was looked at in. Verified in the app on a scratch project rather
  than only in tests: a flowchart, a sequence diagram with `autonumber` and a
  state diagram previewed beside a pipe table and a Swift code block, a fence
  that does not parse showing its code and its line, and a fence naming its own
  theme drawn in it with the notice under it.
- ~~**Exporting a fence, which is the whole of what is left of the above.**~~
  **Done.** Both questions were answered by deciding rather than by drawing, and
  both answers are written out in full where the code is — `DiagramExport.fenced`
  for the naming and `DiagramExport.export(markdown:)` for the gesture. In short:

  - **Which block does somebody mean? All of them, so there is no gesture.**
    `Export ▸ PNG (Dark)` over the document — the same four items, in the
    preview's own menu and in the tree's — writes every fence. The two rejected
    candidates were rejected on the same ground rather than on taste: a menu on
    the attachment under the pointer exists only where there is a picture on
    screen, so the *tree* would have needed a different answer, and 0429 says
    every export has to be reachable from both places. One act with two
    behaviours is exactly the drift this code keeps collapsing into one place —
    and it would also make re-exporting a README four gestures with four
    separate answers. A submenu listing the blocks needs each block to have a
    name before it can list them, which was the *other* open question, and a
    list whose entries read "the second one, the third one" is a choice between
    things nobody can tell apart. Writing all of them is what `mermaid-cli -i
    README.md` does, and it is the decision the `.drawio` export already made
    about pages for the same reason: a folder holding one of a document's four
    pictures is the quiet wrongness these rules exist to avoid.

  - **What are four pictures out of one file called? After the diagram, and
    after its place only when it has no name.** `README.md` with a fence whose
    front matter says `title: Checkout` writes `README-checkout.png`; an
    untitled fence writes `README-<n>.png`, counting **every** drawable block in
    the file from 1 so that titling one does not renumber the others. The first
    fence to claim a name keeps it, so a title typed today never renames a
    picture written last week; a title that slugs to nothing, or to something a
    position could have produced (`3`, `3-dark`), falls back to the position.

    Mermaid's front matter `title:` is used and its `title` *line* directive is
    not, deliberately: the line form exists in some diagram types and not
    others, and in a flowchart `title Overview` is two nodes — so a picture named
    after it would be named after part of itself. The **preceding heading** was
    rejected because it is not part of the diagram: four fences under one
    `## Architecture` all want the same name, and rewording a section for how it
    reads would rename a picture the README points at. The **info string**
    (```` ```mermaid checkout.png ````) was rejected as a convention invented
    here that nothing else reading Markdown would honour.

    **There is never a bare `README.png`**, not even for a document with one
    fence in it. A Markdown document is not a diagram, so a picture named after
    the whole file would claim to be a picture of the document — and `README.md`
    and `README.puml` sit in one folder quite happily, where they would
    otherwise both write `README.png`.

    What it costs, said rather than hidden: an untitled block inserted above
    another still renumbers everything below it, which is the cost the `_001`
    rule has and this only halves. The way out of it is in the naming itself —
    give the diagram a title and its picture stops moving.

  `-dark` composes rather than fights: `README-checkout-dark.png`,
  `README-2-dark.png`. A **fence** that states its own look is drawn that way and
  keeps the plain name, which is 0429's rule applied a block at a time because a
  look is stated a block at a time — so one export of a mixed document writes
  `README-1-dark.png` beside `README-2.png`, and the notice says so rather than
  leaving it to be found. A document counts as having stated a look only when
  *every* fence has, since that is the only case where offering `PNG (Dark)`
  would offer a difference that does not exist.

  **No new stamp**, which was 0429's one worry about a second name: `refusal`
  reads the bytes of whatever is already at those paths and never the name, so
  every one of these files is protected and replaceable by exactly the rules
  `diagram.png` is. And **no second renderer**: a fence exports through
  `MermaidRenderer.shared` and the same five fixes the pane draws through, so
  the export cannot drift back into black wedges for edges.

  `Export ▸` appears over a `.md` only when there is a ```` ```mermaid ```` block
  in it — `DiagramExport.holdsADiagram` is the contents question where
  `isDiagram` is the name question — because an Export over every Markdown file
  in a repository would be wrong far more often than right.

  Verified in the app on a scratch project rather than only in tests: a document
  of three fences of three kinds exported from the rendered preview's own menu in
  both formats, every written file opened and looked at (three distinct
  pictures, dark, signed, the titled one drawing its own title), the SVGs
  rasterised through CoreSVG as the same pictures, and the same document with a
  fourth fence that does not parse writing **nothing at all** — not even the
  three that drew perfectly well — and saying
  `README.md line 61: Expecting '()', 'SOLID_OPEN_ARROW', … or 24 others, got
  'NEWLINE'`.
- ~~**The theme.**~~ **Done, in 0429**, which decided it for all three tools
  rather than for this one: the file wins, the app's theme is the default, and an
  export asks for the one it wants by name (`Export ▸ PNG (Dark)` writes
  `diagram-dark.png`).
- ~~**ELK layout** (`@mermaid-js/layout-elk`) is a second bundle and is not here.
  A diagram asking for `layout: elk` gets Mermaid's own message about it.~~
  **Not vendored, and the sentence above was wrong about what happens instead.**

  Measured rather than guessed, both halves. **The package**: 3.1 MB as a
  tarball, and what a page would actually load is a 356-byte ESM entry that
  `import()`s one chunk of **1.64 MB** minified — a 46% increase on the 3.57 MB
  this app carries to draw Mermaid at all, for a second way of arranging the
  same flowchart. And it is **ESM only**, with a relative import: the page
  Mermaid is loaded into has *no origin at all* (`loadHTMLString` with no base
  URL, navigation refused), which is the property this entry treats as enforced
  rather than intended, and a relative `import()` needs an origin to resolve
  against. So it would cost either a scheme handler of its own — `DrawioEditor`
  has one, so the mechanism exists and this would be the second page to need it
  — or a blob-URL trick to get a module in without one.

  **And what a diagram asking for it gets today is not a message.** A flowchart
  with `layout: elk` in its front matter draws, and the drawing is byte for byte
  the one the same flowchart draws with no front matter at all: Mermaid has no
  loader for a layout it was not given and quietly uses its own, saying nothing.
  That is worse than the entry claimed, and it is worse than an error — the
  picture is right and is arranged the way somebody did not ask for.

  So the layout is not vendored and the silence is fixed instead:
  `Mermaid.statedLayout` reads the same two spellings `statedLook` does, and the
  pane and a Markdown fence say one line under the drawing — *This diagram asks
  to be laid out by "elk", which is not in this build, so it is drawn with
  Mermaid's own layout.* The same place, and the same register, as 0429's
  sentence about a file that sets its own colours, for the same reason: a
  picture that quietly ignores what the file asked for is a bug report waiting
  to happen. `MermaidLiveTests` pins the silence itself, so a later Mermaid that
  starts refusing instead fails the test rather than leaving a caption that
  lies.

  Worth revisiting if somebody actually wants ELK — the numbers above are the
  cost, and none of them is prohibitive; what is missing is a reason.
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
- ~~**A shot in `Scripts/screenshots.sh`.**~~ **Taken.** `shoot diagram` opens
  the examples repository's `mermaid/` and photographs `document.mmd` — the
  source on the left, the state diagram on the right, at `Fit · 95%`. It is in
  `docs/images/diagram.png` and the landing page shows it, with a card and a row
  in the feature table beside it, because a picture nobody is shown is not
  documentation.

  Two decisions in it worth knowing. **Mermaid rather than PlantUML**, which is
  the honest choice rather than the flattering one: a `.puml` needs a container
  runtime and a pulled image, so a machine taking these pictures without either
  would photograph an install hint. **`document.mmd` of the six**, because it is
  the one whose whole picture fits the pane at a size somebody can read — the
  flowchart in `render.mmd` is taller than the window and photographs with its
  bottom cut off, and the sequence diagram fits only by shrinking to 54%.

  One thing found while taking it, and it is nothing to do with diagrams: the
  app's own toasts land in the capture. Three shots in a row had *zsh needs you*
  and *a subagent finished* over the bottom right corner, because a Claude Code
  hook on this machine reaches whichever Abydos is running — including a
  headless one taking screenshots. Worth its own entry; the shots here were
  retaken until the corner was clear.
- ~~**The pane draws through `NSImage`,** which is CoreSVG, which is why so much
  of the flattening above exists. It is the right dependency to have — the file
  written to disk is better for it — but if a diagram ever appears that CoreSVG
  still cannot draw, the honest answer is to show the pane a bitmap rasterised
  by the web view at the zoom being asked for, and keep the drawing for the
  file.~~ **Asked, and the answer was no — but not for the reason expected.**

  The condition was "if a diagram ever appears that CoreSVG still cannot draw",
  and the only way to answer that was to go and look. Every one of the
  twenty-two kinds of diagram this Mermaid draws was drawn twice — once through
  `NSImage`, once through the web view's canvas — and the two rasterisations
  compared pixel for pixel, with a pixel or two of slack for the fact that the
  two round a drawing's size differently.

  **Three of them came apart, and all three were this app's own doing.** They
  are written out where the code is and summarised in the commit; in short, a
  Sankey lost every flow (77% of the page different) to a `url("#id")` this app
  wrote with the quotes a computed value carries; a journey lost every label to
  the empty-label sweep taking away the `<text>` half of a `<switch>` the
  browser had not laid out; and a treemap's labels were drawn half a line low
  **in the export** because Mermaid's own inline `style` beat the attributes the
  bake writes to neutralise it. Fixed, all three, in the flattening — where the
  fix helps the pane, the exported SVG, Preview.app and anything else that is
  not a browser, which a bitmap in the pane would have helped none of.

  What is left between the two renderers is **0.01% to 0.76% of the page**: the
  edges of glyphs and a pixel of rounding. Nothing was found that CoreSVG cannot
  draw once the file stops asking for a browser.

  So a bitmap is not built, and there are two reasons beyond "nothing needs it".
  **The pane being wrong is the alarm that the file is wrong.** They are the same
  drawing, and every fault above was found because somebody could see one of
  them — a bitmap pane would have shown a perfect journey diagram while the SVG
  written beside it had no labels at all, and nobody would have known until they
  opened the file somewhere else. And **it would cost the sharpness**: a drawing
  is a drawing at any zoom, and a bitmap rasterised at the zoom being asked for
  has to be rasterised again on every ⌘+ — a second path, a second cache, and a
  pane that is soft for the moment between.

  What was built instead is the thing that makes the question answerable next
  time: `MermaidEveryKindLiveTests` draws all twenty-two, compares the two
  renderers, and asserts the three faults as properties of the file. If a
  diagram type does appear that CoreSVG genuinely cannot draw, that test names
  it and says by how much — and *then* this decision is worth taking again, with
  a case rather than a hypothetical.

  Two known differences that are not faults and are not fixed. `mix-blend-mode`
  is a CSS property CoreSVG has no answer for, so overlapping Sankey flows will
  blend in the exported PNG and not in the pane; and an *animated* edge stops
  animating in a file, which was already recorded above.

## Steps

Written when the item was picked up again, long after the rest of it: the three
bullets above that are not struck through are the whole of what was left, and
this is what each of them comes to once it is looked at rather than guessed at.
The first of them is a question before it is work, so it is asked first.

- [x] Ask, with a measurement rather than a memory, whether CoreSVG is still
      short of the web view: every diagram type this Mermaid draws, rasterised
      both ways and compared pixel for pixel
- [x] Fix whatever of that difference turns out to be this app's own doing
- [x] Keep the comparison as a test, so the next diagram type that comes apart
      says so rather than waiting to be found in a pane
- [x] Decide the bitmap-in-the-pane question on that evidence, and write the
      decision down whichever way it goes
- [x] Decide ELK on its measured cost, and write the numbers down whichever way
      it goes
- [x] A `diagram` shot in `Scripts/screenshots.sh`, and somewhere in the
      documentation that shows it
- [ ] Write down here what was ruled out on the way
- [ ] The spec says what the project now does

---

Its number is where it sits in the queue, not what it is worth doing next.
