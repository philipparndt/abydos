# 426. draw.io, a diagram somebody drags rather than types

Every diagram this app draws so far is **text that renders to a picture**.
PlantUML and Mermaid (0425) are both the same shape of thing: a file somebody
types, a pane that draws it, an `Export ▸ PNG` beside it. The source is the
document and the picture is a derived artefact.

A `.drawio` file is not that. It is **an editor's document** — an `<mxfile>` of
`mxGraphModel` XML, usually deflate-compressed, often several pages — and
nobody types it. People edit a `.drawio` by dragging shapes, and the XML is a
serialisation they are never meant to read. So "support draw.io the way we
support Mermaid" splits into two genuinely different features with an order of
magnitude between them, and choosing which one is the whole of this entry.

## What a `.drawio` file actually is

Established from real files rather than from memory: read out of draw.io's own
`app.min.js`, then written back and round-tripped in a scratch probe, then drawn
by draw.io's own viewer in an off-screen `WKWebView`.

- **The root is `<mxfile>`, and one `<diagram name id>` per page.** Multiple
  pages are siblings, not a nesting. A three-page file is three `<diagram>`
  elements and there is no single picture of it.
- **The payload is plain `<mxGraphModel>` XML *or* compressed**, and compressed
  is the common case: **all 155** of the diagram templates draw.io itself ships
  are compressed, and not one is plain. The scheme is `Graph.compress` —
  `base64( deflateRaw( encodeURIComponent(xml) ) )`. The `encodeURIComponent`
  step is the trap: inflating and stopping there gives a string full of `%20`
  that parses as XML and is wrong everywhere a label had a space in it.
- **`.drawio.svg` is a real SVG** with the whole `<mxfile>` in a `content`
  attribute on the root element. draw.io's reader tries three encodings in
  order: raw (`<`), URI-escaped (`%`), then base64.
- **`.drawio.png` is a real PNG** with a `tEXt` or `zTXt` chunk keyed `mxfile`
  or `mxGraphModel`, holding URI-escaped XML — `+` for space, and `zTXt`
  zlib-deflated on top.

Those last two are the "editable picture" variants, and they matter more here
than the plain form does, because they are what people commit to repositories:
one file that GitHub renders *and* draw.io reopens.

## How far to go, which is the decision

### 1. ~~View only~~ — done, 2026-08-09

Draw a `.drawio` to a picture in the preview pane, and `Export ▸ PNG` / `SVG`
beside it exactly as PlantUML and Mermaid do. The file is read-only input, like
a `.puml`, and the app never writes it.

Measured, on this machine, against draw.io **v31.1.8** (2026-08-06):

| | |
|---|---|
| Vendored, fully offline | **11.3 MB** |
| Page load, once | **0.50–1.19 s** |
| First render | **0.03–0.17 s** |
| Every render after | **0.003–0.020 s** |

The 11.3 MB is `js/viewer-static.min.js` (3.95 MB), `js/stencils.min.js`
(7.23 MB), `styles/` (0.12 MB) and `mxgraph/images` + `mxgraph/css` (0.02 MB).
Loaded into an off-screen `WKWebView` with `baseURL: nil` and every asset path
pointed at an unreachable scheme, it drew a three-page compressed file and an
AWS-stencil file with **nothing fetched at all**. `GraphViewer` decompresses the
payload and counts the pages itself, so the app does not have to implement the
format above merely to show one.

### 2. ~~View, and edit in place~~ — done, 2026-08-09

Embed the draw.io **editor** in the pane — the real one, sidebar and all — and
write the file back. This is what people actually want from draw.io support, and
it is a different feature, not a bigger version of the first.

Measured the same way: `js/app.min.js` (9.16 MB), `js/stencils.min.js` (7.23 MB),
`js/shapes-14-6-5.min.js` (1.41 MB), `styles/`, `mxgraph/`, `index.html` and
English `resources/dia.txt` come to **18.0 MB**; `img/` for the shape sidebar's
previews takes it to **24.5 MB**; `templates/` (the New-diagram gallery) to
**29.4 MB**; `js/extensions.min.js` (Mermaid, ELK, and the rest) to **33.1 MB**.

The megabytes are not the problem. **The problem is that the app stops owning the
document.** The integration surface is draw.io's embed protocol — `?embed=1&proto=json`
and `window.postMessage` both ways. Read out of `app.min.js`, the app would
*send* `load`, `merge`, `configure`, `dialog`, `spinner`, `status`, `template`,
`layout`, `prompt`, `export`, `exit`, and *receive* `init`, `load`, `save`,
`autosave`, `export`, `exit`, `configure`, `merge`, `prompt`, `template`,
`draft`, `openLink`, `fit`, `size`, `getDiff`, `patch`, `resetDiff`, `shortcut`
and `textContent`.

What that costs, specifically, and each of these is a real question rather than a
worry:

- **`TextDocument` is not in this.** Dirty state, `⌘S`, undo, the tab's edited
  dot and the close-without-saving prompt all read one object that will not
  exist for a `.drawio`. Either a second kind of document appears beside it, or
  a `TextDocument` is kept in step with an editor that does not tell it about
  keystrokes — only about `autosave`, and only every 1.5 seconds (draw.io's own
  `autosaveDelay`).
- **Undo belongs to draw.io.** `⌘Z` in the pane must reach mxGraph's undo stack
  and not the app's, and the app's Edit menu has to know which it is talking to.
- **The watcher will see the app's own writes.** `TextDocument.hasChangedOnDisk`
  compares modification date and size against what it last wrote; a document the
  app does not write through has nothing recorded, so every save looks like an
  external change. And a *genuine* external change — `git checkout` on a branch
  with a different diagram — has to reach draw.io as a `load`, which discards
  whatever is in its undo stack.
- **Saving is not atomic in the way the rest of the app's saving is.**
  `TextDocument.save` writes with `.atomic`. A `save` event carries XML from
  another process's idea of the document, and the app has to decide whether to
  trust it when the file underneath has moved.

### 3. Edit through the app's own model

Parse `mxGraphModel` into the app's own structures and draw it in AppKit. **Not
worth it, and it should not be proposed again**: mxGraph's shape language is
defined by 2.24 MB of shape JavaScript and 40.8 MB of stencil XML that this app
would be reimplementing and then permanently trailing, and the first file
draw.io saves with something new in it would not open.

## Recommended: 1 first, 2 second — and 1 is worth shipping on its own

Level 1 at 11.3 MB with nothing to install and no container is close to free,
given 0425 has already built the surface it needs. A repository full of
architecture diagrams becomes readable without leaving the editor, which is
genuinely most of what a `.drawio` in a codebase is for — they are read far more
often than they are edited.

More to the point, **level 1 does all of level 2's homework except the hard
part**: the vendoring and its licences, the offline asset problem below, the
file format, the page question, the export naming. It leaves out exactly one
thing — document ownership — which is the thing that could go wrong quietly and
lose somebody's work. Doing it second, deliberately, against a viewer that
already works, is much better than discovering it while also debugging a build
that will not draw.

One thing level 1 must get right that PlantUML and Mermaid did not have to: a
`.drawio` should **open in `.preview`, not `.splitRight`**. `FilePreview.defaultMode`
gives `.plantuml` a split because checking the text against the picture is the
whole of the work; for a `.drawio` the text is a serialisation nobody reads, and
it belongs with `.model` — which already opens rendered for exactly this reason.

## Where it comes from, and under what licence

**Source:** `github.com/jgraph/drawio`, release **v31.1.8**, the single asset
`draw.war` (53.1 MB, unpacking to 143.8 MB). The `.war` is the webapp; it is the
same tree the desktop app and `viewer.diagrams.net` are built from, and it is
the only artefact the project publishes. There is no npm package — `drawio` on
npm is an unrelated charting tool by somebody else.

**Licence:** **Apache-2.0**, confirmed against the repository rather than
assumed. Two things travel with it that are not Apache-2.0 and belong in
`THIRD-PARTY-NOTICES.md` on their own rows:

- **`stencils/` and `img/` carry their own LICENSE**, which is Apache-2.0 plus a
  clause forbidding use of the icon sets in Atlassian products or anything
  distributed through the Atlassian marketplace. That does not touch this app,
  and it explicitly does not touch diagrams people export. It has to be
  reproduced, not paraphrased.
- **`templates/` is CC-BY-4.0**, which is a reason not to ship it — and level 1
  does not need it at all.

The vendoring follows what 0425 established and `Sources/Grammars/` established
before it: the files under `Sources/AbydosKit/Preview/drawio/`, their `LICENSE`
beside them, a pinned `VERSION`, a refresh script in `Scripts/`, and rows in the
notices. Nothing auto-updates.

**Size, said plainly:** `Sources/` is 12 MB today and Mermaid adds 3.6 MB. Level
1 adds 11.3 MB and level 2 adds 18–25 MB. That is a repository and an
application bundle roughly three times their present size, for one file type.
It is the strongest argument against doing this at all, and it should be made to
somebody before anybody starts.

## The one thing 0425's surface cannot do as it stands

`WebRenderer` guarantees that **nothing is fetched, ever**: one document, script
inlined, `baseURL: nil`, and `Keeper` cancels every navigation that is not the
document itself. That guarantee is right and worth keeping.

draw.io's viewer defaults `STENCIL_PATH`, `SHAPES_PATH`, `STYLE_PATH`,
`GRAPH_IMAGE_PATH` and `mxBasePath` to `https://viewer.diagrams.net/…` and
**loads shape libraries lazily, by style prefix, at draw time**. Under
`WebRenderer` those fetches are cancelled — and here is the part that matters:
**they fail silently.** Measured, with and without the stencil bundle, on a file
using one AWS shape: with it the SVG carries two `<path>` elements, without it
one. No error, no message. The diagram simply draws short of its icons and looks
like a diagram.

All five are `window.X = window.X || …` defaults, so setting them before the
bundle loads is enough — and `js/stencils.min.js` turns out to be exactly the
right answer, because it is not a file list but an **override of
`mxStencilRegistry.loadStencil`** that serves all 40.8 MB of stencil XML from
memory, deflated, in 7.23 MB. Which is why the offline set above is 11.3 MB and
not 47.

So: the surface needs a way for a page to declare its own asset globals, and the
guarantee to hold. Nothing here needs a base URL or a scheme handler. What is
**not** covered by `stencils.min.js` is `img/lib/` — 5.67 MB of clipart that
`shape=image` cells reference by path — and a diagram using it would show
nothing where a picture goes, silently, in the same way. Whether that is worth
5.67 MB, or worth detecting and saying, is a real question and is left below.

## What it reuses unchanged, and what needs something new

Unchanged, and this is most of it:

- **`DiagramPaneView`** — white paper, fit-to-pane, following `⌘+`, a sentence
  when there is no picture, and the right-click `Export ▸ PNG` / `SVG`. A
  `DrawioPreviewView` subclass is the same shape as `MermaidPreviewView`.
- **`DiagramExport.destinations`** — `x.png` for the first and `x_001.png` for
  the rest. Written for a `.puml` holding several `@start` blocks, and it maps
  onto draw.io's pages exactly. That is luck, but it is the right answer.
- **`DiagramExport.refusal`** — a picture nobody here drew is not overwritten.
- **`DiagramExportCommand`** — both gestures, the Toast register, the
  `abydosDiagramExported` notification that selects the written file in the tree.
- **`WebRenderer`'s** load-once, deadline, idle-reap machinery, subject to the
  section above.

New, and small:

- **`FilePreview.Kind.drawio`**, one case and one extension row — except that
  `url.pathExtension` says `svg` for `architecture.drawio.svg`, which is the one
  place the existing detection is wrong for this file type. Today that file is
  `Kind.image`, previews as a picture and reads as text, which is arguably
  already correct; leaving it alone at level 1 is defensible and should be a
  decision rather than an oversight.
- **`DiagramStamp.marker`** is the single string `"abydos-mermaid"`. A third
  drawer needs it to be per-tool, or needs draw.io's own stamp read instead —
  which exists, and is better: a `.drawio.png` this app wrote should carry the
  `mxfile` chunk, and that chunk *is* the proof it was drawn from a diagram.

Not reused at all: `PlantUML.Tool`, `ToolImages`, `ContainerImageStore`. Nothing
is installed and nothing is pulled.

### The container route, since 0425 asked the same question

Rejected without pulling, on the published figures. `jgraph/export-server` is
**433 MB compressed and amd64 only** — no arm64 image at all, so on this machine
it is Rosetta emulation of a headless Chromium to draw a box. `jgraph/drawio` is
411 MB and does have arm64, but it is Tomcat serving the same static files that
are already sitting in `Sources/`. Both are worse than 11.3 MB in the bundle, by
the same reasoning and by a wider margin than Mermaid's.

## Where "a picture beside the file" stops being the obvious operation

Worth saying, because the export was designed three days before this and fits
almost too well.

For text-that-draws, `diagram.png` beside `diagram.puml` is a derived artefact:
regenerate it, commit it, never touch it by hand. For draw.io the equivalent is
`architecture.drawio.png` — **one file that is both the picture and the
document**, which is the form draw.io itself pushes and the form that makes a
diagram render on GitHub and still reopen. Writing a plain `architecture.png`
beside `architecture.drawio` is correct and should exist, but it is probably not
the operation people reach for, and "Save a copy as an editable PNG" may be the
one that earns its place. Level 1 can write it — the model XML is in hand and
the chunk format is above — and it is a decision about menus, not about
machinery.

And **pages break the one-file-one-picture assumption in a way `@start` blocks
did not**. Three `@startuml` blocks in a file are three diagrams somebody chose
to put together. Three pages in a `.drawio` are one document, and exporting all
three every time is probably wrong — but so is exporting only the one on screen
without saying so. The pane needs a page control before the export can be
honest, and that control does not exist for any current file type.

## What is deliberately left to decide

- **Whether to do this at all**, given the section on size. 11.3 MB for viewing
  and 18–25 MB more for editing, against a 12 MB source tree.
- **`img/lib`** — 5.67 MB more so clipart draws, or leave it out and accept a
  silent gap. Either way, whether a missing asset can be made to *say so* rather
  than drawing a diagram that looks finished.
- **The `.drawio.svg` / `.drawio.png` question**, both directions: are they read
  as diagrams or left as pictures, and is the editable variant something this
  app writes.
- **Level 2's document model**, which is the real work and should be its own
  entry once level 1 has landed: a second kind of document beside `TextDocument`,
  or `TextDocument` driven by `autosave` events. Not guessed at here.
- **Whether the editor gets the shape sidebar's `img/` and the templates
  gallery**, which is 6.5 MB and 4.9 MB of "does this feel like draw.io".
- **An example to work against.** The examples repository holds no `.drawio`,
  and for the same reason 0424 and 0425 both ask for one: a preview either draws
  or it does not, and the screenshot harness points at that repository. It wants
  a plain one-page file, a compressed multi-page one, one using a stencil
  library, and a `.drawio.svg` — those four are exactly the cases above.

**A note for whoever wires this up:** `WebRenderer`'s own doc comment points at
"backlog 0425" for what draw.io would need. It means this entry, which is 0426.

---

## What was built, and what it cost — 2026-08-09

Both levels, in one sitting, and the second was smaller than this entry feared.
`.drawio` and `.dio` open in draw.io's real editor — sidebar, format panel, page
tabs, the lot — over a `TextDocument` this app still owns, and
`Export ▸ PNG` / `SVG` writes every page beside the file.

### The vendored set: 27 MB, not 11.3 or 18

`Scripts/vendor-drawio.sh`, `Sources/AbydosKit/Preview/drawio/`, v31.1.8.
Measured in SI megabytes, where this entry's figures above were MiB:

| | |
|---|---|
| `js/app.min.js` | 9.60 |
| `js/stencils.min.js` | 7.59 |
| `js/viewer-static.min.js` | 4.14 |
| `js/extensions.min.js` | 3.85 |
| `js/shapes-14-6-5.min.js` | 1.48 |
| `images/` less `sidebar-*.png` | 0.28 |
| `styles/`, `mxgraph/`, `resources/dia.txt` | 0.22 |
| **total** | **27.1** |

Three things in that table are corrections to what is written above.

- **`extensions.min.js` is not optional, and this entry has it as a nicety.**
  `App.main` loads `shapes-14-6-5.min.js`, `stencils.min.js` **and**
  `extensions.min.js` itself and does not reach its own callback until all three
  have arrived. Without the third the editor loads, builds no `EditorUi`, and
  the pane says "Opening draw.io…" for ever with nothing in the console.
- **`images/sidebar-*.png` is 6.12 MB of the 6.40**, and it is only the preview
  sprites in the More Shapes dialogue. Dropping it costs one dialogue's
  thumbnails and saves a quarter of the whole vendoring.
- **The viewer needs `shapes-14-6-5.min.js` too**, which the 11.3 MB figure
  above does not include. `stencils.min.js` covers stencils, which are XML;
  shapes implemented in *JavaScript* — `mxgraph.aws4.resourceIcon`, most of the
  cloud icon sets — would be fetched one file at a time from `SHAPES_PATH`, and
  a cell whose shape does not resolve is drawn as a **plain rectangle** with
  nothing said. That is the same silent gap the stencils would have, one layer
  up, and it was found by a test rather than by looking at a picture.

### `img/lib` and `math4`: not carried, and made to say so

Both are answered 404 by the editor's own scheme handler, which **writes down
every path it cannot serve** — so a third thing going missing is a failing test
(`everythingTheEditorNeedsIsInThisBuild`) rather than a diagram with a hole in
it. `Drawio.notCarried` names them in one place.

- **`img/lib/`** — 5.95 MB of clipart. `Drawio.clipartNotice` reads the model
  for `img/lib/` references, and the pane says so once rather than drawing an
  empty box in silence.
- **`math4/`** — 3.3 MB of MathJax, which draw.io asks for on *every* load and
  which only a diagram typesetting LaTeX uses. One that does draws its formulas
  as the text they are written as.

### The two settings that make a picture a picture

Level 1's real work turned out not to be the vendoring. It was the same lesson
0425 learned about Mermaid, twice:

- **`mxSvgCanvas2D.prototype.foEnabled = false`.** mxGraph's default puts every
  label in a `foreignObject` full of HTML. Mermaid's `htmlLabels`, in a
  different tool.
- **`mxUtils.lightDarkColorSupported = false`**, and this one is new. Recent
  draw.io writes every colour **twice** — the plain value as a `fill` attribute
  and `style="fill: light-dark(rgb(237,113,0), rgb(216,109,12))"` beside it — so
  one file follows the reader's theme. WebKit understands `light-dark()`, so the
  pane and the rasterised PNG were both correct; **CoreSVG does not, and paints
  the element black rather than falling back to the attribute.** The exported
  AWS diagram opened in Preview.app as five solid black boxes with its labels
  gone. Turned off, every colour is written once, as itself, and the CoreSVG
  rendering is pixel-identical to the browser's.

Both are flags draw.io provides. Neither is a search-and-replace over somebody's
diagram, which would have been the worse thing to own.

### The decisions this entry left open, and how they went

- **`FilePreview.Kind.drawio`**, `.preview` and **no source half at all**
  (`hasReadableSource` is false). Not a nicety: a `CodeView` and draw.io over
  the same file, neither aware of the other's edits, is the one way this feature
  could lose work. It also means the app's own undo stack has nothing to act on
  in a `.drawio` tab, which is how ⌘Z stays draw.io's without arbitration.
- **`architecture.drawio.svg` and `.drawio.png` stay `Kind.image`.**
  `pathExtension` says `svg`, they render on GitHub, and the editor is one
  `.drawio` away. What the app *does* take out of one is its `<mxfile>`, so a
  picture it exported is recognised as a diagram rather than a screenshot.
- **Pages: no control of this app's.** draw.io's own page tabs are along the
  bottom of the editor, so the thing this entry asked for already exists inside
  the pane. **Export writes every page**, `x.png` then `x_001.png`, and the
  notice says how many — the tree's Export has no page on screen to mean, and a
  folder holding a third of a document is exactly the quiet wrongness the export
  rules exist to avoid.
- **The stamp is per-tool** (`DiagramStamp.Tool`), and the export *also*
  recognises draw.io's own `mxfile` chunk, which this entry was right that it is
  better: the chunk is proof the file came from a diagram. Every picture
  exported from a `.drawio` carries it, so `architecture.png` is not only a
  picture of the diagram but the diagram, and opens again in draw.io with all
  its pages. "Save a copy as an editable PNG" needs no menu item — the ordinary
  export is one.

### Level 2, and why "the app stops owning the document" did not happen

The premise above is that a `.drawio` needs a second kind of document beside
`TextDocument`, or a `TextDocument` driven by 1.5-second `autosave` events.
**Neither.** `TextDocument` is already the right model: the file is UTF-8 XML,
it tracks dirty state, it writes atomically, and it records what it wrote so
`hasChangedOnDisk` is false afterwards. What changes is only which *view* edits
it. So:

- The pane listens to **mxGraph's own model change event**, not draw.io's
  autosave timer, and calls `TextDocument.setContents` — a new method that
  replaces the buffer without touching the undo history and without firing
  `onTextChanged`, because that notification is how an *external* change reaches
  the pane and a loop between an editor and its document is how drawings get
  lost. The edited dot appears when the shape is dropped.
- **⌘S, the close prompt and auto-save are unchanged code.** `save()` gained one
  branch that asks the editor for its document first, because somebody may press
  ⌘S while still holding the shape they dragged.
- **The watcher does not bounce.** The app's own write goes through
  `TextDocument.save`, which records the disk state. A genuine external change
  reaches the pane as `onTextChanged` and is loaded into draw.io, losing its
  undo stack — the same trade the text editor already makes.
- **Round-trip.** `Editor.defaultCompressed` is set from what was read.
  draw.io's own default is *plain*, so without this every file draw.io ever
  wrote would become a diff thousands of lines long the first time somebody
  moved a box.

### What the embed protocol actually is, read out of `app.min.js`

Three things cost real time and are worth having written down:

1. **`initializeEmbedMode` refuses unless
   `(this.embedMessageSource || window.opener || window.parent) != window`** —
   and what it leaves behind when the test fails is not "no protocol" but a
   **disabled graph**. A top-level `WKWebView` is its own parent and has no
   opener, so the editor loaded, drew nothing and could not be clicked. The
   editor therefore runs in an **iframe** and the app talks to its host page,
   which is what the protocol was written for. The two are same-origin, so the
   host also reaches the `EditorUi` directly for what the protocol has no
   message for.
2. **`App.main` takes a callback carrying the `EditorUi`**, and draw.io's own
   `main.js` throws it away. It is called by hand for that reason.
3. **A `WKURLSchemeHandler` must answer with an `HTTPURLResponse`.** draw.io
   fetches its string bundle with `XMLHttpRequest` and checks `status` against
   200–299; a bare `URLResponse` reports **0**, `App.main` never calls back, and
   the pane says "Opening draw.io…" with nothing in the console. Half an hour.

Also: `bootstrap.js`'s `mxscript` is **not** safely stubbed out. draw.io calls it
for optional extras and *waits on the callback*; a stub that does nothing hangs
`App.main`. `DrawioEditorPage` implements it.

### What it costs and what it is worth

`Sources/` was 12 MB; Mermaid took it to 16 and this takes it to 43.2, and the
built `.app` is 122 MB. That is the argument against, and it has not gone away —
it is now a fact rather than an estimate. Against it: a repository full of
architecture diagrams is readable *and editable* without leaving the editor, on
a machine with nothing installed and no network at all, and the four commits
below are the whole of it.

### Still open

- **An example to work against.** The fixtures used here are
  `Tests/AbydosKitTests/Fixtures/{plain,pages,stencils}.drawio` — a plain page, a
  compressed three-page file and one using both a stencil and a JavaScript
  shape. The examples repository still has none, and the screenshot harness
  points there.
- **A `.drawio.svg` the app writes as a file somebody edits.** It reads one; it
  does not offer to save one under that name.
- **The More Shapes dialogue's thumbnails**, which are the 6.12 MB left behind.
- **MathJax**, likewise, at 3.3 MB.

---

Its number is where it sits in the queue, not what it is worth doing next.
