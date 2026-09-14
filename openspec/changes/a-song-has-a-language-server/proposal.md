## Why

Asked for on 2026-09-13, on the evening the song pane landed: "we can even
add a LSP to mat — think this would greatly help abydos". A `.song` opens as
plain text with no colouring, no completion and no problems: a misspelt
instrument is found by the render, twenty seconds later, as an error strip
over the pane, and the settings a block takes are looked up in
`docs/FORMAT.md`. Every other language somebody writes here has a server
that says these things while they type.

There is no originating `.abydos/backlog` item: this comes from a direct
request, and the backlog is retired.

## What Changes

- **`mat lsp`**, in musik-as-text (commit `5b924d6` on `main`, 2026-09-14): a
  language server over stdin and stdout, a subcommand of the same binary
  the song pane renders with. Diagnostics as you type — the parser's and the
  arranger's, with their hints; completion of block keywords, of the
  settings a block takes by its instrument's kind, of a setting's `key=`
  options, and of the names the song defines; hover on keywords and on
  names; go-to-definition for instruments, patterns and tracks; the blocks
  as document symbols.
- **Abydos knows the language.** `.song` is the `song` language: commented
  with `#`, named *Song* where languages are named, answered for by `mat lsp`
  — found the way every tool is, with the `cargo install` line as the hint
  when it is not.
- **No grammar.** The file stays uncoloured, as PlantUML does; a grammar is a
  vendoring decision of its own.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `language-servers`: a new requirement — a song's server is its renderer.

## Impact

- **AbydosKit**: `LSP/LanguageServers.swift` gains the definition;
  `Syntax/LanguageRegistry.swift` the extension and the name;
  `Syntax/CommentSyntax.swift` the comment. Three lines of data and a test.
- **musik-as-text**: a new crate `crates/mat-lsp` (lsp-server, lsp-types)
  and the `Lsp` subcommand in `mat-cli`; `mat-core`'s lexer becomes public
  for it.
