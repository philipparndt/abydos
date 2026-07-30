# Third-party notices

ideai redistributes the components below. Every one permits redistribution in an
open-source project, commercial or otherwise. Their licence texts ship with the
source and inside the built `.app`.

## Bundled font

**Hack Nerd Font Mono** — `Resources/Fonts/`, licence in
`Resources/Fonts/LICENSE-Hack.md`.

Hack is a composite work with three licences, all permissive:

| Component | Licence | Obligation |
|---|---|---|
| Hack | MIT (© 2018 Source Foundry Authors) | Include the notice |
| Bitstream Vera Sans Mono | Bitstream Vera License (© 2003 Bitstream Inc.) | Include the notice; do not use the reserved names "Bitstream" or "Vera" in a derived font name |
| DejaVu | Public domain | None |

Two conditions worth stating explicitly, since both are satisfied here:

- The Bitstream Vera License permits selling the font **as part of a larger
  software package** but not on its own. Bundling it inside an application is
  exactly the permitted case.
- The reserved font names are only restricted for *derived fonts*. The font is
  shipped unmodified under its own name, so nothing is renamed.

The Nerd Fonts patch adds glyphs and is itself MIT-licensed; the patched output
keeps the upstream licences above.

## Parsing

**tree-sitter** and its grammars — MIT.

Grammars consumed as Swift packages: bash, c, cpp, go, html, java, json,
markdown, openscad, rust, svelte, swift, toml, typescript.

Grammars vendored into `Sources/Grammars/` (see the note in `Package.swift` for
why): css, javascript, python, yaml. Each keeps its upstream `LICENSE` beside
its sources.

**SwiftTreeSitter** (ChimeHQ) — BSD.

## What ideai does *not* bundle

These are invoked if installed, never redistributed, so their licences do not
apply to this project:

- `git`
- `go`, `dlv` (Delve)
- `claude` (Claude Code)
- Fork, if present, for "Open in Fork"

## Refreshing

`Scripts/vendor-grammars.sh` re-fetches the vendored grammars and copies each
upstream `LICENSE` alongside its sources. If you add a grammar, make sure its
licence lands next to it — MIT requires the notice wherever the source is
redistributed.
