## 1. TypeScript inherits JavaScript

- [x] 1.1 `LanguageDefinition` gains `inherits: String?`; `configuration(for:)`
      joins the base bundle's `highlights.scm` (and `injections.scm`,
      `locals.scm` where both exist) ahead of the language's own and compiles
      the text with `Query(language:data:)` against the inheriting grammar.
      TypeScript and TSX name `javascript`.
- [x] 1.2 `SyntaxTests`: the TypeScript sample asserts a keyword, a string, a
      call and a constant by kind, not merely that a token appeared; a test
      that the joined query compiles for `typescript` and `tsx`, naming the
      pattern when it does not.

## 2. The renderer

- [x] 2.1 `MarkdownRenderer`: one body size read as `Theme.current.scaled(14)`
      at render time; every heading size, code size, spacing, padding and the
      text container inset a proportion of it or a scaled constant.
- [x] 2.2 A fence's lines share one `NSTextBlock`: padded, on a surface
      blended a fixed step from `editorBackground` toward `editorText`, zero
      paragraph spacing, code line height 1.45. Both fence paths — grammar
      and none — go through it; the unlanguaged path sets `editorText`, and
      `gitAdded` and `gitModified` leave the file.
- [x] 2.3 Headings: sizes 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85 of the body,
      more space above than below, a bottom-edge border in `separator` on
      levels one and two via a block, level six dimmer. The thematic break is
      a block with a top-edge border and no dash characters.
- [x] 2.4 Body at 1.5 line height and a body height between paragraphs;
      hanging list markers; a block quote with a left-edge border and dimmer
      text; links in the scheme's `HighlightKind.link` colour, here and in the
      view's `linkTextAttributes`.
- [x] 2.5 Inline code: 85 % of the body, marked with a private
      `.abydosInlineCode` attribute and no background attribute; a
      `NSLayoutManager` subclass draws a rounded, padded pill for runs
      carrying it. `MarkdownPreviewTextView` is built on that layout manager
      in `makePreviewView`, and the commit-message pane in `HistoryPane`
      adopts the same one.
- [x] 2.6 A `NSTextBlock` subclass rounds the code panel's corners in
      `drawBackground(withFrame:in:characterRange:layoutManager:)`.
- [x] 2.7 Whatever of the sizing is pure arithmetic — the proportions, the
      blend — lives in AbydosKit as a small type with `MarkdownTypographyTests`
      asserting the proportions and that the panel surface clears the themes
      spec's contrast rule against `editorText` for every shipped theme.

## 3. Proving it

- [x] 3.1 A fixture README under the scratchpad with an unlanguaged fence, a
      `ts` fence holding the Playwright line, `#` and `##` headings, inline
      code in a sentence, a wrapping bullet, a quote and `---`. Built as
      `de.rnd7.abydos.mdpreview` with an unpinned UUID, a `--markdown
      --screenshot` run against a scratch copy, the window's project asserted
      first; one shot before the change and one after, both recorded in the
      design under a dated heading.
- [x] 3.2 The same run at zoom 2.0, and a copy of the code panel compared to
      the fence's text.
- [x] 3.3 Any docs screenshot showing a preview re-taken — none exists:
      `Scripts/screenshots.sh` takes no `--markdown` shot.

## 4. Before finishing

- [x] 4.1 One `##` in the next version's release notes, in the shape of 0.20.6:
      the markdown preview is set like a page, and TypeScript is coloured.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate the-markdown-preview-is-set-like-a-page`.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `markdown-preview` is new and
`editor` is what this change amends.
