## Why

Asked for on 2026-09-22: "would be nice to have the same preview as for
markdown also for html docs".

A `.md` opens as its text with *Preview*, *Split Right* and *Split Down* in the
tab bar, and clicking one renders the document beside the source. A `.html`
opens as text and nothing else: `FilePreview.kind(for:)` answers `nil` for it,
so `availableModes(for:)` is empty, the tab bar draws no preview control, and
*Toggle Markdown Preview* is disabled because `Tab.isMarkdown` asks for
`languageId == "markdown"`. There is no way to see the page a file makes
without leaving the app for a browser and coming back — which is the same
complaint that produced the markdown pane, the Mermaid pane and the picture
pane before it.

This is a gap rather than a decision. Every other file in this app whose
rendered form is the point of it has a pane: a `.mmd` gets its diagram, a
`.puml` gets its diagram, a `.scad` gets its shape, a `.svg` gets its picture
*and* its text. HTML is the oldest file in that family and the only one still
missing, and the machinery it needs is already here twice over — `WebRenderer`
loads a page with no origin and refuses every navigation off it, and
`DrawioEditor` serves a whole directory of assets to a web view through a URL
scheme of this app's own.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **A `.html`, `.htm` or `.xhtml` has a preview.** `FilePreview.Kind` gains
  `.html`, so the tab bar's control offers *Source*, *Preview*, *Split Right*
  and *Split Down*, the session remembers which was chosen, and `--preview-mode`
  can drive it. Nothing else has to learn about HTML to make that work.
- **It opens as source**, exactly as a `.md` does, and for the same two
  reasons: an HTML file is read as well as rendered, and a generated report of
  several megabytes should not be rendered because somebody clicked its name.
  The preview is asked for once and remembered thereafter.
- **The pane shows the buffer, not the file on disk.** Typing in the source
  half updates the page, debounced like the markdown pane's, and the page keeps
  its scroll position across the re-render so an edit near the bottom of a long
  document does not throw the reader back to the top.
- **Relative assets resolve.** A stylesheet, a script or a picture named by a
  relative path is read off the disk beside the file, through a scheme handler
  of this app's own — the `DrawioEditor` pattern — so the page looks the way it
  looks in a browser.
- **Nothing is fetched.** A request that leaves the file's own directory tree,
  and any request for `http:`, `https:` or anything else remote, is refused and
  counted, and the pane says how many were refused and where the first one
  pointed. An HTML document in a repository is often full of CDN tags and
  tracking pixels, and a preview pane that quietly fetched them would make
  opening a file a network event. The count is the honest half of that trade,
  and `DrawioAssetScheme` already keeps exactly this sort of tally for the
  clipart this build leaves out.
- **A click goes where a click should.** A link to a remote address opens in
  the browser rather than replacing the pane, which is what the markdown
  preview's links already do. A link to a file beside it opens that file in a
  tab. The pane itself never navigates away from the document it is showing.
- **The preview follows the zoom**, as the markdown preview does: ⌘+ grows the
  page with the rest of the interface.
- **The menu command is no longer about markdown.** *Toggle Markdown Preview*
  becomes *Toggle Preview* and works for any tab with a readable source and a
  rendered form, which is what it always described. The driven `--markdown`
  flag keeps working and is joined by nothing new — `--preview-mode` already
  says the rest.

## Capabilities

### New Capabilities

- `html-preview`: what the HTML pane shows and what it refuses — the buffer
  rendered as a page, relative assets read off the disk, remote requests
  refused and counted, links opened rather than navigated, scroll kept across
  an edit, and the page following the interface's zoom.

### Modified Capabilities

- `previews`: *A file whose rendered form is the point of it opens showing
  both* names which kinds open how, and HTML joins markdown as a kind that is
  read as well as rendered and so opens as itself. *A preview nobody has looked
  at yet costs nothing* gains the HTML pane: no web view is built until the
  preview is on screen.

## Impact

- **AbydosKit**: `Project/FilePreview.swift` gains `.html` — the kind, the
  three extensions, `defaultMode` returning `.source`, and `hasReadableSource`
  answering true. `Preview/HtmlPage.swift` (new) is the pure half: which
  requests a document's own tree allows, the refusal tally, and the resolution
  of a relative reference against the file's directory. `Preview/HtmlScheme.swift`
  (new) serves the buffer for the document itself and on-disk bytes for
  everything under its directory, answering 404 and recording anything else —
  `DrawioAssetScheme` is the model, and its containment test is the one to copy.
- **AbydosApp**: `Editor/HtmlPreviewView.swift` (new) is the pane — the web
  view, the debounced reload, the kept scroll offset, the navigation policy and
  the line that says what was refused. `Editor/EditorViewController+Preview.swift`
  gains its `case .html` in `makePreview(for:)` and binds the buffer to it the
  way the Mermaid pane is bound. `Editor/EditorViewController.swift` grows a
  `Tab.canPreview` beside `isMarkdown`, and `AppDelegate+Menu.swift` and
  `MainWindowController+Layout.swift` follow it for the renamed command.
- **Tests**: `HtmlPreviewTests` for the pure half — extensions, default mode,
  containment, refusal counting — and a live suite for the pane in the manner
  of `DrawioEditorLiveTests`, which is where the reload keeping its scroll and
  the refused remote request are checked.
- **No new dependency**: WebKit is already linked for Mermaid and draw.io.
- **No `.abydos/backlog/spec` file is made untrue**: the backlog is retired.
