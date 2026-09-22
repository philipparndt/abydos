## 1. The kind, in AbydosKit

- [x] 1.1 `FilePreview.Kind` gains `.html`, with a comment saying why HTML is
  here and what it is not — not an editor, unlike `.drawio`, and not a picture,
  unlike `.svg`.
- [x] 1.2 `kind(for:facts:)` answers `.html` for `html`, `htm` and `xhtml`, and
  nothing for `vue`, `xml`, `xsd`, `xsl`, `pom` or `svg`.
- [x] 1.3 `defaultMode(for:facts:)` answers `.source` for `.html`, beside the
  `.markdown` case, carrying the argument from the design: read as well as
  rendered, and the one kind that is routinely machine-written and enormous.
- [x] 1.4 `hasReadableSource(_:)` answers true, so all four modes are offered.
  `hasDedicatedViewer` and `isPlayable` stay false.
- [x] 1.5 `HtmlPreviewTests`: the three extensions preview and the five
  look-alikes do not, `.svg` is still a picture, the default mode is `.source`,
  and `availableModes` is all four.

## 2. What the page may reach

- [x] 2.1 `Preview/HtmlPage.swift`: resolving a request path against the file's
  directory, standardising symlinks, and answering whether it is contained by
  it. `DrawioAssetScheme`'s containment test is the model.
- [x] 2.2 In the same file, the count of remote references written in a
  document — the absolute `src` and `href` addresses — returning how many and
  the first of them, for the pane's line. No document is altered.
- [x] 2.3 Tests: `../..` out of the directory is refused, a symlink pointing
  out is refused, a sibling and a subdirectory are allowed, a document with
  three CDN tags counts three and names the first, a document with none counts
  none.

## 3. Serving the document

- [x] 3.1 `Preview/HtmlScheme.swift`: a `WKURLSchemeHandler` under
  `abydos-html` that answers the document's own path from a closure over the
  buffer and every other path from the disk beneath the file's directory,
  404s and records anything else, and gives each file the media type its
  extension names. `DrawioAssetScheme` is the shape.
- [x] 3.2 The compiled `WKContentRuleList` that blocks every load whose URL is
  not this scheme, compiled once and reused across panes.
- [x] 3.3 Tests: the document's own path comes back as the buffer rather than
  the disk after an edit, a `style.css` beside it is served, a climb out is
  404'd and recorded, and the rule list compiles.

## 4. The pane, in AbydosApp

- [x] 4.1 `Editor/HtmlPreviewView.swift`: the web view, the scheme handler, the
  rule list, `allowsContentJavaScript` following the project's trust, and the
  navigation delegate that refuses everything but this scheme.
- [x] 4.2 `show(_:)` loads the buffer, debounced at 0.3 s like the markdown
  pane, reading the page's scroll offset before the reload and putting it back
  when the load finishes.
- [x] 4.3 The line the pane says: how many remote references were not loaded
  and the first of them, shown only when there were any; and, in an untrusted
  project, the trust sentence with the gesture that grants it.
- [x] 4.4 A click on a remote link opens the browser; a click on a link to a
  file beside it opens that file in a tab. The pane never navigates.
- [x] 4.5 `pageZoom` follows `Theme.current.scale`, and a theme change is told
  to the pane rather than rebuilding it.

## 5. Wiring it up

- [x] 5.1 `EditorViewController+Preview.swift` gains `case .html` in
  `makePreview(for:)`, binding the document to the pane the way the Mermaid
  pane is bound and nothing being built until the pane is made.
- [x] 5.2 `Tab.canPreview` beside `Tab.isMarkdown` in
  `EditorViewController.swift`, and `toggleMarkdownPreview` renamed and
  regated on it.
- [x] 5.3 *Toggle Markdown Preview* becomes *Toggle Preview* in
  `AppDelegate+Menu.swift`, with `MainWindowController+Layout.swift` and
  `EditorAreaController+Forwarding.swift` following the rename. `--markdown`
  keeps working.

## 6. Driving and checking it

- [x] 6.1 A live suite in the manner of `DrawioEditorLiveTests`: a page with a
  stylesheet and a picture beside it renders both; a page naming three CDN
  addresses fetches none and says three; an edit to the buffer reaches the
  pane and leaves the scroll where it was.

  `HtmlPreviewLiveTests` covers the first two and the buffer, and the driven
  run covers the edit reaching the pane. **The scroll across a re-render is
  not covered by anything that runs**: the pane is in `AbydosApp`, which has
  no test target, and no driven flag scrolls a web view. Real events posted
  from outside would reach it — `design.md` says so under *Found while
  building*.
- [x] 6.2 Check by hand against a scratch project under the scratchpad, driven
  with `--trust`, a seeded defaults domain and `--preview-mode preview`, built
  with `make build BUNDLE_ID=de.rnd7.abydos.html PIN_UUID=0` and run from
  `build/`. Never `make install`.
- [x] 6.3 The same run untrusted, checking the scripts did not run and the
  sentence offering trust is on screen.

## 7. Finishing

- [x] 7.1 The two open questions in `design.md` are answered in it as they are
  settled — what a link to a sibling does, and whether `--html` is wanted.
- [x] 7.2 `docs/release-notes-<version>.md` gains one `##` for the HTML
  preview: what it does and the two rules that matter, nothing is fetched and
  scripts need trust. One short paragraph, 0.20.6's shape.
- [x] 7.3 `make test` and `make warnings`, both clean, exit codes read rather
  than output skimmed. Any file that grew past its recorded size has its record
  bumped in the same change.

## Notes

No `.abydos/backlog/spec/*.md` file is made untrue: the backlog is retired, and
what this change makes untrue is `openspec/specs/previews/spec.md`, whose two
requirements are carried in `specs/previews/spec.md` as modified.
