## Why

The maintainer, 2026-09-17, with two pairs of screenshots: the same README
rendered by Abydos's markdown preview and by GitHub. Set side by side, the
preview reads as text with attributes on it and GitHub's reads as a page, and
every difference has one cause in `MarkdownRenderer`:

- **A fenced code block is a run of paragraphs, not a block.** Every line in a
  fence ends a paragraph, and a paragraph in the preview carries eight points
  of spacing after it, so seven lines of shell come out with a blank line's
  worth of air between each — the first screenshot's most visible fault. The
  block has no background, no padding and no edge; nothing says where the code
  starts and the prose stops except the change of font.
- **A fence with no language is green.** `.codeBlock` paints its text in
  `gitAdded`, the colour a file is when it is new to git, because that was the
  nearest green to hand. GitHub sets plain code in the body colour on a darker
  panel.
- **A `ts` fence is barely coloured.** In the second pair, GitHub colours
  `await`, `async`, the strings and the call names; Abydos colours the one
  identifier that begins with a capital. The TypeScript grammar's own
  `highlights.scm` is thirty-five lines of type patterns and nothing else —
  upstream expects it to *inherit* the JavaScript queries, and this project
  loads it alone. The editor colours a `.ts` file the same thin way; the
  preview only made it visible beside a page that did not.
- **Headings float.** GitHub draws a rule under an `h1` and an `h2` and gives
  every heading a margin above it larger than the one below. The preview's
  headings are bigger text with fourteen points above and six below.
- **The type is set tight.** Body 13.5 pt with two points of leading and eight
  between paragraphs; GitHub sets 16 px at a line height of 1.5 with a
  paragraph's height between paragraphs. Inline code is a bare
  six-per-cent-white rectangle behind the glyphs; GitHub's is a pill with room
  around the letters. A thematic break is a string of dashes.
- **None of it follows the zoom.** `bodySize` is a constant. The interface's
  zoom, which `scaled-controls` requires of every control, leaves the preview
  at 13.5 pt while the tree, the tabs and the editor beside it grow.

There is no originating `.abydos/backlog` item: this comes from the screenshots
above.

## What Changes

- **A code block is one block.** Its lines are laid out in a single
  `NSTextBlock` with a background surface a step off the editor's, padding on
  all four sides and no per-line spacing, so the panel is the shape of the
  code. This is the same mechanism the tables already use for cells, and it
  reaches the commit-message pane in git history for free, which renders with
  the same function.
- **Code is coloured by grammar or not at all.** A fence with no language, or
  one no grammar answers for, is set in the body colour on the panel. No git
  status colour is used for anything in the preview.
- **TypeScript inherits JavaScript.** The registry compiles the TypeScript and
  TSX highlight queries from the vendored JavaScript `highlights.scm` followed
  by the grammar's own additions, so a `ts` fence — and a `.ts` file in the
  editor — is coloured as fully as a `js` one. The syntax test that samples
  every grammar names the keyword, the string and the call it expects
  TypeScript to colour.
- **Headings are set like a page's.** Sizes in proportion to the body — 2,
  1.5, 1.25, 1, 0.875 and 0.85 times — with a rule under levels one and two,
  more space above than below, and a level six in the dimmer text colour.
- **The type is set to read.** Body at 1.5 line height, a body height between
  paragraphs, inline code on a pill with room around the letters, a thematic
  break that is a drawn line, list markers hanging in the margin, and a block
  quote with a bar down its left edge.
- **The preview follows the zoom.** Every size comes from the body size, and
  the body size comes from the theme's scale, so ⌘+ grows the preview with the
  window the way it grows everything else; the debounced re-render already
  runs when the theme changes.
- **Not in scope:** a maximum measure for the text column, a copy button on a
  code block, GitHub's exact colours or its font. The preview is set in the
  system font on the theme's surfaces; GitHub is the reference for the
  *shape* of a page, not its palette.

## Capabilities

### New Capabilities

- `markdown-preview`: how a rendered markdown document is set — its blocks,
  its type, its code, and that it follows the zoom. The preview has been in
  the app since before the backlog was kept and no spec describes it; this is
  the first.

### Modified Capabilities

- `editor`: TypeScript is coloured as JavaScript plus its own additions, in a
  file and in a fence alike.

## Impact

- **`Sources/AbydosApp/Editor/MarkdownRenderer.swift`**: block styling
  rewritten around `NSTextBlock` for code, headings, quotes and rules; sizes
  derived from one scaled body size; git colours removed.
- **`Sources/AbydosApp/Editor/MarkdownDiagrams.swift`**:
  `MarkdownPreviewTextView` gains a layout manager, or the text blocks gain a
  subclass, to draw a pill behind inline code and rounded corners on a code
  panel — see the design for which.
- **`Sources/AbydosApp/Editor/EditorViewController+Preview.swift`**: link
  attributes read the scheme's link colour; the text container inset scales.
- **`Sources/AbydosKit/Syntax/LanguageRegistry.swift`**: a language definition
  can name a base whose `highlights.scm` its own is appended to; TypeScript
  and TSX name JavaScript.
- **`Tests/AbydosKitTests/SyntaxTests.swift`**: the TypeScript sample asserts
  the kinds it expects, not merely that some token appeared. A new
  `MarkdownTypographyTests` covers whatever of the sizing is factored into
  AbydosKit as pure arithmetic.
- **Driving**: a `--markdown --screenshot` run on a scratch copy of a README
  with an unlanguaged fence, a `ts` fence, two heading levels, inline code, a
  quote, a list and a rule, taken before and after, and kept in the design.
- **Release notes** for the next version, one `##`.
