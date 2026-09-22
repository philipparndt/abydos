## Context

Three panes in this app already draw with WebKit, and none of them fits HTML.

`WebRenderer` keeps one off-screen web view warm with a single inlined document
in it, loaded with `baseURL: nil`, refusing every navigation, and answers
questions by calling into the page. It is a drawing surface for Mermaid: one
document, no origin, no subresources. Its own comment says it is a seam and not
a plugin system, and a second document with a directory of assets behind it is
not what it is for.

`DrawioEditor` is the nearer relative. It serves draw.io's own files to a
visible web view under a scheme of this app's own, `abydos-drawio`, because the
editor fetches its strings, stylesheet and icons by relative path and a
`loadHTMLString` page has no origin to resolve them against. Its
`DrawioAssetScheme` answers every request from one directory, refuses anything
that climbs out of it, and *records* what it refused — which is how a missing
piece of clipart stopped being a silent gap.

The markdown pane is the behaviour being asked for: a `.md` opens as text, the
tab bar offers three ways to see it rendered, the rendered half follows the
buffer rather than the file on disk, the re-render is debounced at 0.3 s, and
the scroll position survives it.

What a `.html` gets today is none of that. `FilePreview.kind(for:)` falls to
`default: return nil`, `availableModes` is therefore empty, the tab bar draws
no control, and `toggleMarkdownPreview` is guarded by `Tab.isMarkdown`.

## Goals / Non-Goals

**Goals:**

- A `.html`, `.htm` or `.xhtml` has the same four modes as a `.md`, remembered
  in the session and drivable with `--preview-mode`.
- The pane shows the buffer, so an unsaved edit is visible.
- Relative stylesheets, scripts and pictures load off the disk beside the file.
- Nothing leaves the machine, and what was refused is said rather than left as
  a blank rectangle.
- The pane costs nothing until somebody looks.

**Non-Goals:**

- **Not an editor.** draw.io owns its document because its XML is unreadable;
  HTML is text somebody types, so the source half is the editor and the pane is
  a picture of it. Nothing comes back out of the web view.
- **No export.** The diagram panes write a PNG or an SVG beside the file
  because a diagram is made to be embedded somewhere else. A page is not, and
  "print to PDF" is a browser's job.
- **No live reload of a site.** One file is rendered. A page that is one route
  of a dev server is somebody's browser's business, and this app has a terminal
  to start that server in.
- **No devtools, no console.** If a page misbehaves, the browser is two
  keystrokes away.

## Decisions

### The pane is a `WKWebView`, not an `NSAttributedString`

AppKit will read HTML into an attributed string, and the markdown pane is an
`NSTextView`, so matching it exactly would mean rendering HTML into text and
putting it on the same kind of page. Ruled out on two counts. It lays out
almost nothing — no flexbox, no grid, no script — so a real page arrives
looking broken rather than looking like itself, which is worse than no preview
at all. And the HTML importer fetches remote subresources itself, on the
calling thread, which is the one thing this pane must never do.

### The page is served through a scheme handler, not loaded from disk

Three ways to get a document into a web view, and only one of them does the
job:

- `loadFileURL(_:allowingReadAccessTo:)` renders **the file on disk**. An
  unsaved edit would not appear, which breaks parity with the markdown pane on
  the first keystroke.
- `loadHTMLString(_:baseURL:)` renders the buffer, and a page loaded this way
  has no read access to the directory its `baseURL` names. Relative assets
  fail. This is precisely why `loadFileURL(_:allowingReadAccessTo:)` exists,
  and why `DrawioEditor` gave up on `loadHTMLString` for the same reason.
- A scheme handler of this app's own — `abydos-html` — answers the document's
  own path from the buffer and every other path from the disk beneath the
  file's directory. The buffer is rendered, relative references resolve, and
  every subresource the page asks for arrives at code this app wrote.

The third is the only one where the refusal tally is implementable at all, and
it is the pattern already in the building. **Ruled out:** writing the buffer to
a temporary copy beside the file and loading that. The `previews` spec forbids
rendering by writing into the project, `go3mf` recipes were moved out of the
project for exactly this in 0.22.0, and a stray `index.abydos.html` appearing
in `git status` while somebody types is the failure that rule is about.

### What the tree allows, and what is refused

The handler serves paths under the **file's own directory**, resolved and
symlink-standardised, and nothing else. Not the project root: a `docs/` folder
with an `index.html` in it should reach its own `style.css`, and an HTML file
should not be a way to read every file in the repository through a `../..`.

A reference that climbs out, or names a file that is not there, is answered 404
and recorded — the `DrawioAssetScheme` behaviour exactly.

An absolute `https:` reference never reaches the handler, because WebKit
fetches it itself. Blocking it needs a `WKContentRuleList` compiled once and
reused, blocking every load whose URL is not this app's scheme. The navigation
delegate is the second gate rather than the first: it sees navigations, not
subresources, so a delegate alone would refuse a click on a link and quietly
fetch a tracking pixel.

**Counting is separate from blocking, and approximate on purpose.** A content
rule list blocks silently — WebKit does not report what it dropped. So the
count comes from reading the document's own `src` and `href` attributes for
absolute remote addresses, before it is loaded, and the pane says "3 remote
references were not loaded — the first is `https://cdn.…`". **Ruled out:**
rewriting every remote URL in the document to the app's own scheme so that the
handler sees them and can count them exactly. It makes the tally perfect and
the page a lie — a script that reads its own `src`, or builds a URL from one,
would see an address that does not exist. A count that is honest about being a
count of *references written in the file* is worth more than an exact count of
requests bought by editing the file.

### JavaScript runs only in a trusted project

The `project-trust` spec draws its line at starting what the project supplies,
and allows "the previews this app renders itself" while a project is untrusted.
The markdown, Mermaid and model panes are this app rendering. A page's own
`<script>` is the project's code, and running it because somebody clicked
*Preview* on a file they have not read would put project code on the far side
of that line on the strength of a file extension.

So `allowsContentJavaScript` follows the project's trust, and an untrusted
project's preview says the same sentence every other refusal says and offers
the same one gesture. In a trusted project scripts run, because a coverage
report that cannot sort its columns and a documentation page whose tabs do
nothing are the two HTML files anybody most wants to look at.

**Ruled out:** running scripts always, on the argument that the content process
is sandboxed and has no network. It is a good argument about damage and the
wrong argument about the rule — trust here is about whose code starts, not
about how far it could get.

### It opens as source

A `.md` opens as text and the preview is asked for. HTML gets the same answer
for the same two reasons, and one more of its own.

It is read as well as rendered: half the HTML in a repository is a template
somebody is editing, where the text *is* the work.

And HTML is the one kind here that is routinely machine-written and enormous. A
coverage report or a generated API document is megabytes of markup, and
`defaultMode` is consulted when a file is opened — including the provisional
tab a single click makes while somebody arrows down a directory. **Ruled out:**
`.splitRight`, the `.puml` and `.scad` answer. Those are files written *in
order to* make the rendered thing, which is the test that requirement states,
and a hand-written page passes it. But the kind cannot tell one from the other
from its name, and the cost of being wrong is asymmetric: a preview nobody
wanted costs a WebContent process and a multi-megabyte parse, where a preview
somebody wanted costs one click, once, remembered thereafter.

### Which extensions

`html`, `htm`, `xhtml`. Not `vue`, `xml`, `xsd`, `xsl` or `pom`, all of which
`LanguageRegistry` maps to the HTML *grammar* — a Vue component is not a page
and a POM is not a page, and rendering either produces a blank rectangle with
the text of the file in it. Not `svg`, which is already `.image` and must stay
so: the picture pane is the right pane for it, and `architecture.drawio.svg`
landing there is a decision `FilePreview` already records.

### Keeping the scroll across a re-render

The markdown pane re-renders into the same text view and puts the scroll offset
back. A web view has to be reloaded, which loses the page's scroll position, so
the offset is read out of the page before the reload and restored when the
load finishes. **Ruled out:** diffing the new document into the live DOM to
avoid the reload. It needs a morphing library — a dependency, which needs a
written reason — to avoid a reload that costs milliseconds on a file of the
size anybody hand-edits.

The debounce is the markdown pane's 0.3 s, for the same reason the Mermaid pane
gives: a document half way through being typed is not a document, and reloading
between two characters flashes a broken page.

### The pane is built when it is looked at

`makePreview(for:)` is called when a mode with a preview in it is chosen, so the
web view exists only from then. The idle reaper `WebRenderer` keeps is not
copied: that exists because an off-screen renderer is invisible and could sit
warm all day. This pane is on screen, and leaving the mode or closing the tab
discards it.

A theme change tells the pane rather than rebuilding it, which is the lesson
`DrawioPreviewView` records: a rebuild would take the scroll position and any
state the page's own script holds.

## Risks / Trade-offs

- **A script that builds a URL at runtime is blocked but not counted** → The
  rule list still refuses the request, so nothing is fetched; the pane's line
  undercounts. Accepted: the alternative is rewriting the document, which is
  ruled out above. If this bites, the honest fix is a WebKit-side report of
  blocked loads, not a cleverer parse.
- **A page that expects a server** — one that fetches its own data with
  `fetch('/api/…')` — renders empty and says three references were refused,
  which reads as a broken preview → The notice names what was refused, so the
  reason is on screen rather than guessed at. Rendering one route of a running
  site is a non-goal.
- **A huge generated report is slow to render** → It is asked for rather than
  opened into, and the parse happens in the WebContent process, so the window
  keeps drawing. This is the argument for `.source` as the default, and it is
  the whole of the mitigation.
- **A runaway script hangs its process** → Out of process, so the window
  survives and the tab can be closed or put back to *Source*. No watchdog is
  proposed; the deadline `WebRenderer` uses exists because a call must return,
  and nothing here is waiting on an answer.
- **The refusal line is one more thing on screen** → It appears only when
  something was actually refused, the way the clipart notice does.

## Settled while building

- **A link to a sibling file opens a tab.** The pane cancels the navigation and
  hands the file to the editor, so the tab bar never names one document while
  the pane shows another. A documentation tree of linked pages therefore opens
  one tab per page, which is what every other way of opening a file in this app
  does. An anchor into the document itself is allowed through, so `#section`
  still works.
- **No `--html` flag.** `--preview-mode` sets any mode on any file and was all
  the driven checks needed. `--markdown` keeps working and now toggles whatever
  the tab in front is, since the command it drives is no longer about markdown.

## Found while building

- **A driven screenshot could not see the page.** `WindowCapture` draws the
  window with `cacheDisplay(in:to:)`, which walks the view tree — and a web
  view's content is composited out of this process, so four runs came out as
  the pane's own background with the caption underneath it and nothing said
  why. The repository already had the answer: `SnapshotDrawable`, which
  `DrawioPreviewView` conforms to for the same reason. The pane now answers
  with a picture of the page, painted into the part of its rectangle the web
  view occupies so the caption underneath survives.
- **The scroll position across a re-render is not covered by a run.** The pane
  reads it out of the page before the reload and puts it back on `didFinish`,
  and nothing drives a scrolled preview today: the driven flags can type into a
  file but cannot scroll a web view. Posting real events from outside would
  reach it, which is how the window-gesture work got its evidence.
