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
was not really a competition once the pull finished.

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

## Two things about the SVG that had to be fixed rather than passed through

- `mermaid.render` returns `<svg width="100%" style="max-width: 282px">`, which
  is right for a page and wrong for a file: an SVG with no intrinsic size is
  drawn by a browser into a default 300×150 box, and the first PNG rasterised
  from one came out 172×300 instead of 564×982. The root element gets explicit
  `width`/`height` in pixels off its own `viewBox` before anything is written or
  drawn — pure, and tested as such.
- **`htmlLabels` is turned off.** Mermaid's default puts labels in a
  `foreignObject` full of HTML, which a browser draws and Preview.app,
  `librsvg`, Inkscape and a canvas do not. Turning it off makes the labels
  `<text>` — so the exported file is a picture everywhere, and rasterising it
  works at all.

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

## What is left

- **Fenced blocks in Markdown**, above. The largest missing piece by far.
- **The theme.** Both panes draw on white paper, because that is what PlantUML's
  default background is and matching it was the honest thing. Mermaid has a
  `dark` theme built in and following the editor's would be a nice thing and a
  decision about what an *export* then contains, which must not follow the
  screen.
- **ELK layout** (`@mermaid-js/layout-elk`) is a second bundle and is not here.
  A diagram asking for `layout: elk` gets Mermaid's own message about it.
- **An example to work against.** The examples repository beside this one holds
  no Mermaid. It should hold a `.mmd` flowchart and a sequence diagram, for the
  same reason 0424 wants devcontainers there: the screenshot harness points at
  it, and a preview either draws or it does not.

---

Its number is where it sits in the queue, not what it is worth doing next.
