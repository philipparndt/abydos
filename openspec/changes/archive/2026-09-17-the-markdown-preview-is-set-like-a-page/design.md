## Context

The preview is `MarkdownRenderer.render`, which turns Foundation's
`AttributedString(markdown:)` parse into an `NSAttributedString` for a plain
`NSTextView`, with no web view — that decision is deliberate and stays. The
structure Foundation gives back is `PresentationIntent` components; every bit
of appearance is this file's. Pipe tables are already laid out with
`NSTextTable`, and Mermaid fences and pictures are `NSTextAttachment`s, so the
text system's block machinery is already in use here for the hard cases and
simply never reached the ordinary ones.

The screenshots the proposal cites were taken at different scales, so nothing
below quotes a pixel from them. GitHub's stylesheet is the reference for
proportion: body 16 px at line height 1.5, paragraph margin one body height,
headings at 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85 of the body with a rule under
the first two, code at 85 % of the body on a panel with 16 px of padding and
line height 1.45, inline code at 85 % on a pill padded 0.2 em by 0.4 em.

Two things on this machine shape the work. `MarkdownRenderer` lives in
AbydosApp, which has no test target; what can be tested is what is factored
into AbydosKit. And the grammar bundles are loaded by
`LanguageRegistry.configuration(for:)`, which compiles the queries found in
one bundle's `queries/` directory and nothing else.

## Goals / Non-Goals

**Goals:**

- A code block is visibly one block, with the code's own line spacing.
- Headings, paragraphs, quotes, lists and rules are set in the proportions of
  a rendered page, and every size follows the theme's scale.
- No colour in the preview means something else elsewhere in the app.
- TypeScript is coloured as fully as JavaScript, in the editor and in a fence.
- The commit-message pane, which renders with the same function, gets the
  same code panel without work of its own.

**Non-Goals:**

- Matching GitHub's palette or typeface. The preview is on the theme's
  surfaces in the system font, and the themes spec's contrast rule applies to
  whatever surface the code panel becomes.
- A maximum measure. GitHub caps its column at 1012 px; the preview is half a
  split most of the time and the pane is the measure. Left open below.
- A copy button on a code block, syntax colouring inside inline code, task
  list checkboxes, footnotes, or anything Foundation's parser does not give
  back. Each is a change of its own.
- Rendering while typing any faster or slower than today. The same debounce,
  the same whole-document render.

## Decisions

### A code block is an `NSTextBlock`, not per-paragraph attributes

Every paragraph in a fence carries the *same* `NSTextBlock` instance in its
paragraph style. The text system lays out consecutive paragraphs that share a
block as one block: one background, one padding, one border, drawn once
around all of them. That is exactly how a multi-paragraph table cell is drawn
today, and it is why this is the cheapest correct answer. Inside the block,
`paragraphSpacing` is zero and `lineSpacing` is what gives code its 1.45 line
height; the eight points that separated every line came from the body
paragraph style leaking into code, and they go.

Ruled out:

- **A background attribute per line.** Draws one rectangle per line, hugging
  the glyphs: ragged right edges, no padding, and the gaps between lines show
  the page through. This is what inline code has now and what GitHub's panel
  does not look like.
- **An attachment drawing the code as a picture.** The diagram cell does this
  for Mermaid. Code would stop being selectable text, which is the one thing
  somebody does with a code block in a README.
- **A web view.** Ruled out when the preview was written and nothing here
  reopens it: the cost is a WebKit process per pane and an HTML round-trip on
  every keystroke.

### The block's corners, and the pill behind inline code, are drawn by a subclass

`NSTextBlock` draws a rectangular background. GitHub's panel and pill have a
six-pixel radius, and a rectangle beside the rounded controls the rest of the
window uses reads as a different program. Two ways to round them, with the
same drawing code behind both:

- **A `NSTextBlock` subclass** overriding
  `drawBackground(withFrame:in:characterRange:layoutManager:)` to fill a
  rounded path. Handles the code panel. Cannot handle inline code, which is
  not a paragraph.
- **A `NSLayoutManager` subclass** on `MarkdownPreviewTextView` overriding
  `fillBackgroundRectArray(_:count:forCharacterRange:color:)` to draw a
  rounded rectangle, grown by the pill's padding, for runs carrying a private
  `.abydosInlineCode` attribute, and the default for everything else.
  Handles the pill; the code panel still needs the block.

Chosen: both, one small type each, because they answer different questions —
where a *paragraph's* background goes and where a *run's* does — and neither
can do the other's job. The commit-message pane in git history uses a stock
`NSTextView`, so it gets square pills unless it adopts the same layout
manager; it should, and the task list says so.

Ruled out: **padding the pill with spaces**, hair spaces or otherwise, on
either side of inline code. It changes the text somebody copies out of the
preview, and it is the kind of fix that reads as clever for a week.

### Headings get their rule from the block, not from a drawn line

An `NSTextBlock` on a level-one or level-two heading, with a one-point border
on its bottom edge only in the separator colour and a few points of padding
above the edge, is the rule. The same block, with border on the top edge and
a paragraph containing only a line separator, is the thematic break — which
replaces the string of ten en-dashes the preview draws today. No attachment,
no custom drawing.

### Every size is a multiple of one scaled body size

`bodySize` becomes `Theme.current.scaled(14)`, read at render time rather
than stored, and every other number — heading sizes, code size, spacing,
padding, the text container inset — is a proportion of it or a scaled
constant. The preview then follows ⌘+ the way `scaled-controls` requires of
every control. The render is already re-run when the theme changes, so the
zoom reaches the pane with no new wiring.

Fourteen rather than sixteen: this is a pane in an IDE beside an editor at
the editor's font size, not a page in a browser, and fourteen at 1.5 line
height reads as a page without the preview towering over the source next to
it. **This is a taste decision and is open** — see below.

### Colour comes from the scheme's meanings, never from git's

`gitAdded` on code and `gitModified` on links go. Code with no grammar is in
`editorText` on the panel; links are in the scheme's `HighlightKind.link`
colour, which every scheme already defines for the editor's own link tokens;
a block quote is the dim gutter text colour with a bar in `separator`;
level-six headings are the same dim colour. **The panel surface is the
theme's `currentLineBackground`**: the one ground every theme already made
for coloured code to sit on, a small step off the page toward the text in
each shipped theme — lighter on a dark page, darker on a light one, which is
GitHub's shape.

Ruled out, by a test: **blending the page a fixed step toward the text.** It
was the first design, and `SchemeContrast` extended to the blended panel put
forty syntax kinds of the shipped themes under their floor — the themes are
calibrated to `editorBackground` exactly, so any step toward the text costs
contrast somewhere. A new scheme role was ruled out too: every shipped theme
edited and every user's theme file migrated for one surface. What the
contrast check keeps is `editorText` on `currentLineBackground`, the pair an
unlanguaged fence is set in.

### TypeScript inherits the JavaScript queries by concatenation

A `LanguageDefinition` gains an optional `inherits: String?` naming another
language id. When set, `configuration(for:)` reads the base language's
`highlights.scm` (and `injections.scm`, `locals.scm` where both exist) from
its bundle, appends the language's own, and compiles the joined text with
`Query(language:data:)` against the *inheriting* grammar. The TypeScript
grammar is generated from the JavaScript one and every node the JavaScript
query names exists in it, which is why upstream's own editors do this with
`; inherits: ecma`. TSX inherits the same way.

Ruled out:

- **Copying the JavaScript patterns into a vendored TypeScript query.** Two
  copies of two hundred lines that must be kept the same by hand, in a
  project that vendors grammars specifically so the queries are the
  upstream's.
- **Loading two `Query` objects and running both.** Doubles the cursor work
  on every highlight pass for `.ts` files, and capture precedence between the
  two would have to be invented rather than being what tree-sitter's
  least-specific-first ordering already gives one query.

The risk is a JavaScript pattern naming a node TypeScript renamed; the
compile would fail and the language would fall to uncoloured, which is
today's state for most of it. The task list asserts the compile in a test so
that a grammar bump that breaks it is a red test and not a silent regression.

## Risks / Trade-offs

- **`NSTextBlock` and `widthTracksTextView`** → the table cells already lay
  out under exactly this configuration in exactly this view, so the
  combination is known to work; the code block adds only a block with no
  table. Verified in the driven run rather than assumed.
- **A `NSLayoutManager` subclass on an `NSTextView`** → the view is built
  with a stock layout manager in `makePreviewView`; replacing it means
  building the text container, layout manager and storage by hand. Contained
  to that one function. TextKit 1 is what `NSTextTable` forces anyway, so
  there is no TextKit 2 path to preserve.
- **The panel surface fails the themes spec's contrast rule on some theme** →
  `editorText` on `currentLineBackground` is added to the contrast test the
  themes spec already runs, and every shipped theme passes it.
- **A JavaScript query pattern does not compile against TypeScript** → the
  test named above; fallback is today's colouring, not less.
- **Scaling the preview changes existing driven screenshots** → any docs
  screenshot of a preview is re-taken; the run in the tasks produces them.
- **Selection and copy** → code stays text, pills add no characters, so
  copying a block out of the preview yields the code and nothing else.
  Asserted by the driven run copying the panel and comparing to the fence.

## Open Questions

- **Body size, 14 or 16, and whether it should track the editor font size
  setting instead of a constant.** The design chooses 14 scaled by the zoom;
  the maintainer may prefer the preview to follow the editor's font size so
  source and page grow together under one setting. Either is one line.
- **A maximum measure.** Full-width prose in a wide single pane is long to
  read; GitHub caps at 1012 px. Not done here, because the preview is usually
  half a split, but worth a look once the rest is in.
- **Whether the commit-message pane should get the pill layout manager.** It
  should for consistency; it costs a second construction site for the same
  three lines. Done in the tasks unless the maintainer says otherwise.

## What the driven runs showed, 2026-09-17

Fixture: a scratch project of two files — the maintainer's README's first
half, and a second file with a `ts` fence holding the Playwright line, a
wrapping bullet, a nested item, an ordered list, a two-paragraph quote, `---`,
level three and six headings and a two-column table. Built as
`de.rnd7.abydos.mdpreview` with an unpinned UUID; the domain seeded with one
key; `--trust` so the project opened without the sheet; every run's
`captured … (project mdpreview-project)` line checked.

Three faults found on the way, none visible in a probe of the plain text view
and all three in `NSTextBlock`:

- **A bare block has no width.** The page came out one letter wide. A block
  has to be given `100 %` of the column explicitly; `spanTheColumn` does.
- **A block paints its background over its margins.** The code panel stood on
  the space meant to keep the list off it, and the thematic break — a block
  whose background was the separator colour — came out as a band a paragraph
  tall. The panel subclass insets its paint by the margins, and the rule is a
  bottom border rather than a background.
- **The parser lists intent components innermost first**, not outermost as
  the old comment said. A list item arrived before its list, the depth was
  nought, and the marker table was indexed at minus one. Lists are counted
  before the item is styled.

What the shots show, at 1× dark, 1× light and 2× dark: the `ts` fence
coloured as GitHub colours it; one panel with even padding; pills with room
around the letters and the neighbouring glyphs stepped aside; rules under the
first two heading levels; hanging markers with wrapped lines under the first
word; nested bullets, ordinals, a dim quote with one bar, a drawn rule, and a
table with its right column right-aligned. At 2× every size doubled with the
window. The copy check is by construction rather than by a driven paste: the
room around a pill is a `kern` attribute and paint, and no character is added
for it; the one character the page adds is the zero-width space a thematic
break is set on.

The "before" is the pair of screenshots the proposal opens with, which are the
maintainer's; no build of the old renderer was taken.

Not done here: the body size question stays open at 14 scaled by the zoom.
