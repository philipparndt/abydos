# Third-party notices

Abydos redistributes the components below. Every one permits redistribution in an
open-source project, commercial or otherwise. Their licence texts ship with the
source and inside the built `.app`.

## Bundled font

**JetBrains Mono Nerd Font Mono** — `Resources/Fonts/`, licence in
`Resources/Fonts/LICENSE-JetBrainsMono-OFL.txt`.

| Component | Licence | Obligation |
|---|---|---|
| JetBrains Mono | SIL Open Font License 1.1 (© 2020 The JetBrains Mono Project Authors) | Include the licence; do not sell the font on its own |
| Nerd Fonts glyph patch | MIT | Include the notice |

The OFL permits bundling and redistribution inside a larger work, commercial or
not. Two points worth stating, since both are satisfied here:

- The font is **not** sold on its own; it ships as part of an application, which
  is the permitted case.
- JetBrains Mono declares **no Reserved Font Name**. The name is only restricted
  for modified versions, and even that restriction is inactive here — the font
  is redistributed unmodified under its own name.

Using it does not require any relationship with JetBrains: the OFL grants this
to anybody, for any program.

## Parsing

**tree-sitter** and its grammars — MIT.

Grammars consumed as Swift packages: bash, c, cpp, go, html, java, json,
kotlin, markdown, odin, openscad, rust, svelte, swift, toml, typescript, zig.

Two of those are pinned unusually. **tree-sitter-kotlin** is fwcd's at 0.3.8
rather than the tree-sitter-grammars fork, which ships no queries at all;
**tree-sitter-groovy** (murtaza64) has never tagged a release, so it is pinned
by commit. Both are MIT. Kotlin's `highlights.scm` is derived from
nvim-treesitter's, which is Apache-2.0, and carries that attribution in its own
header.

Grammars vendored into `Sources/Grammars/` (see the note in `Package.swift` for
why): css, javascript, make, python, yaml. Each keeps its upstream `LICENSE` beside
its sources.

**SwiftTreeSitter** (ChimeHQ) — BSD.

## Bundled diagram renderers

**mermaid** 11.16.1 — `Sources/AbydosKit/Preview/mermaid/mermaid.min.js`,
licence in `Sources/AbydosKit/Preview/mermaid/LICENSE`, version in `VERSION`
beside them.

| Component | Licence | Obligation |
|---|---|---|
| mermaid (Knut Sveidqvist and contributors) | MIT | Include the licence |
| what mermaid's own bundle contains — d3, dagre-d3-es, khroma, js-yaml, cytoscape, marked, lodash-es and others | MIT | Include the notice, which travels inside the file |
| DOMPurify 3.4.0 (Cure53), inside the same bundle | Apache-2.0 **or** MPL-2.0 | Include the notice; both permit redistribution unmodified |

It is here because Mermaid has no other form: every command-line Mermaid carries
a headless Chromium, and the one measured for this weighed **2.16 GB** on disk
against this file's 3.6 MB. See backlog 0425.

The file is the upstream UMD build, **unmodified**, and it carries every
component notice above in its own trailing comment — which is what keeps the
obligation satisfied wherever the file goes, including inside the built `.app`.

**draw.io** 31.1.8 — `Sources/AbydosKit/Preview/drawio/`, licences beside the
files, version in `VERSION` there. Taken out of the published `draw.war`, which
is the only artefact the project releases; there is no npm package (`drawio` on
npm is an unrelated charting tool by somebody else).

| Component | Licence | Obligation |
|---|---|---|
| draw.io / diagrams.net (JGraph Holdings Ltd, draw.io AG) — `js/app.min.js`, `js/viewer-static.min.js`, `js/shapes-14-6-5.min.js`, `styles/`, `mxgraph/`, `resources/dia.txt` | Apache-2.0 | Include the licence — `LICENSE` |
| the stencil libraries in `js/stencils.min.js` | Apache-2.0 **plus a rider** | Reproduce it verbatim — `LICENSE-stencils` |
| the icon sets in `images/` | the same rider | Reproduce it verbatim — `LICENSE-img` |
| mxGraph, inside the same bundles | Apache-2.0 | Covered by the above |

The rider on the stencils and icons is Apache-2.0 with one added clause: those
icon sets may not be used in Atlassian products or anything distributed through
the Atlassian marketplace. It does not touch this application, and it says
explicitly that it does not touch diagrams people export with it. It is
reproduced rather than paraphrased, in the two `LICENSE-` files beside the code.

**Not taken, deliberately.** `templates/` — the New-diagram gallery — is
**CC-BY-4.0** rather than Apache-2.0, and an editor opening an existing file
never shows it. `img/lib/` is 5.9 MB of clipart; a diagram using one says so
rather than drawing a gap (see `Drawio.clipartNotice`). `images/sidebar-*.png`
is 6.1 MB of preview sprites for the More Shapes dialogue.

Every file is upstream and **unmodified**. The page the editor runs in is this
project's own — see `DrawioEditorPage` — because draw.io's `index.html` exists
to choose which of a dozen builds to fetch for which host, and none of that has
an answer inside an application bundle.

## What Abydos does *not* bundle

These are invoked if installed, never redistributed, so their licences do not
apply to this project:

- `git`
- `go`, `dlv` (Delve)
- `jdtls` (Eclipse JDT language server) and the java-debug bundle it loads
- `mvn`, `gradle`, and a project's own `mvnw` or `gradlew`
- `claude` (Claude Code)
- Fork, if present, for "Open in Fork"

## Refreshing

`Scripts/vendor-grammars.sh` re-fetches the vendored grammars and copies each
upstream `LICENSE` alongside its sources. If you add a grammar, make sure its
licence lands next to it — MIT requires the notice wherever the source is
redistributed.

`Scripts/vendor-mermaid.sh` does the same for mermaid, taking the version as its
one argument and writing the `LICENSE` and the `VERSION` beside the bundle. The
version above is the only other place it is written down, so change it here too.

`Scripts/vendor-drawio.sh` does the same for draw.io, and takes the three
licence files with it. It also checks two things a new release could quietly
change into a blank pane: that `stencils.min.js` still overrides
`mxStencilRegistry.loadStencil`, and that `viewer-static.min.js` still defaults
its asset paths with `window.X = window.X || …` so the page can set its own.
