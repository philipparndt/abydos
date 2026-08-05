# Third-party notices

ideai redistributes the components below. Every one permits redistribution in an
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

Using it does not require any relationship with JetBrains, and the OFL grants
this independently of the fact that ideai is an alternative to their IDE.

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
why): css, javascript, python, yaml. Each keeps its upstream `LICENSE` beside
its sources.

**SwiftTreeSitter** (ChimeHQ) — BSD.

## What ideai does *not* bundle

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
