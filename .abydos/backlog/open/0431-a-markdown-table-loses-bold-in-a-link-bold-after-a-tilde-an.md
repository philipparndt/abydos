# 431. A markdown table loses bold in a link, bold after a tilde, and its alignment

A shopping list — a GFM pipe table whose delimiter row is `|---|---|---|---:|`
— renders three things wrong in the preview pane, and they were reported as
three bugs. Two of them turn out to be one bug wearing two coats, and the third
is the only one that is honestly ours.

The document is kept as `Tests/AbydosKitTests/Fixtures/shopping-list.md`, cut
down to the shapes that matter: a link whose text contains `**`, a bold cell
that begins with `~`, a `---:` column, a code span in a cell, a `~~struck~~`
cell, an escaped `\|`, and the same constructs again outside the table in a
heading, a list and a blockquote.

## What renders wrong

1. **`[Multiplex Birke **15 mm**, 250 × 125 cm](https://…)`** is a working link
   reading "Multiplex Birke 15 mm, 250 × 125 cm", and the `**…**` is simply not
   applied. The text is right, the destination is right, the emphasis is gone.
2. **`| | | **Summe** | **~ 211 €** |`** renders the third column bold and the
   fourth literally, asterisks and all.
3. **`---:` is ignored.** The prices sit on the left with everything else.

## Whose parser this is

`Sources/AbydosApp/Editor/MarkdownRenderer.swift`, and it is **half ours**.
Blocks and inlines come from Foundation's `AttributedString(markdown:)` — which
is cmark-gfm behind an `AttributedString` — and everything about tables is hand
written on top of it, because Foundation's parser does not understand pipe
tables at all and hands them back as paragraphs with bars in them.

So the split matters: **1 and 2 are inside Foundation and 3 is inside ours**,
and no amount of using Foundation more carefully fixes 1 or 2. Both were
measured against the parser on its own, with no table, no pane and no window
anywhere near them:

    "[a **b** c](https://x.com)"  ->  "a b c"{link}
    "**~ 211 €**"                 ->  "**~ 211 €**"

## 1. Foundation flattens a link's label

Every inline construct inside a link label is parsed, its markers are removed,
and the resulting attribute is thrown away. Measured: `**`, `*`, `` ` `` and
`~~` inside a label all come back as one plain run carrying nothing but the
link. It is not the walk in this file missing a child — there is no child in
what Foundation returns, only a single flat run.

The reverse works: `**[b](https://x.com)**` gives a run that is both bold and a
link. That is the way out, and it is the fix — see below.

## 2. It is not the last cell. It is the tilde.

The report guessed the row splitter was handing the final cell over unparsed, or
swallowing the trailing `|`. **Both are wrong**, and worth writing down so
nobody looks there again: the splitter is fine, and position has nothing to do
with it. `**~ 211 €**` fails in the *first* cell, in a paragraph, in a heading,
with no table in the document at all. `**Summe**` works in the last cell.

What fails is `**` immediately followed by `~` followed by a space:

    "**~ 211**"    ->  literal          "**~211**"    ->  bold
    "**~ a ~ b**"  ->  literal          "**a ~ b**"   ->  bold
    "*~ 211*"      ->  literal          "**~**"       ->  bold

The rule underneath, in cmark's terms: a `~` preceded by punctuation and
followed by whitespace is **right-flanking only** — it can close a strikethrough
and cannot open one. GFM's strikethrough extension pushes it on the delimiter
stack as a closer; nothing before it can open, so cmark records a lower bound at
the position before it and moves on. That position is *the emphasis opener
itself*, and the closing `**` can no longer see past it. `**a ~ b**` survives
because a `~` with whitespace on both sides flanks nothing and is never a
delimiter at all; `**~211**` survives because that `~` can only open.

The damage is bounded: it takes out the pair whose opener it sits against, and
nothing before or after. `**~ a** and **b**` loses the first and keeps the
second.

**This is a defect in the shipped cmark-gfm, not a use of it.** The parsing
options were exhausted — `.full` and `.inlineOnlyPreservingWhitespace` behave
the same, `allowsExtendedAttributes` is already on, and there is no option that
turns the strikethrough extension off.

## 3. Alignment is not read, and could not be expressed if it were

Two questions, and the answers differ:

- **Parsed?** No. `renderTable` says in a comment that row 1 "carries alignment,
  not content" and then drops it on the floor. `splitOutTables` checks the row
  against `"|-: \t"` only to recognise a table.
- **Expressible?** Yes, and cheaply. The table is a real `NSTextTable`, each
  cell already builds an `NSMutableParagraphStyle` that it stamps over the whole
  cell, and `paragraph.alignment` is one line in the place that style is built.

So this one is three small pieces in `MarkdownRenderer` and nothing else.

## What is being done

**Not a different renderer.** Swapping Foundation for tree-sitter-markdown — the
grammar is already a dependency, for colouring the *source* — would mean writing
the whole block and inline walk by hand, several hundred lines, to fix two
inline bugs, and would put the preview's correctness on a grammar chosen for
highlighting. That is the owner's call and not part of fixing three bugs.

Instead, one pre-pass over the **copy of the source handed to the parser** —
never anybody's file, never the text in the editor — plus the alignment work:

- **`MarkdownSource.liftedLinkEmphasis`**: `[a **b** c](url)` becomes
  `[a ](url)**[b](url)**[ c](url)`. Emphasis around a link survives, so the
  markers move outside and Foundation keeps them; adjacent links to the same
  destination merge back into one run, so what comes out is what should have
  come out. Emphasis, strong and strikethrough only.
- **`MarkdownSource.escapedStrayTildes`**: an unmatched right-flanking `~`
  becomes `\~`, which parses as the same character and is no longer a delimiter.
  Tilde runs are paired first, so `~~struck~~` and `~struck~` are untouched, and
  code spans and fenced blocks are skipped.
- **`MarkdownTable`** in the kit: the row splitter (honouring `\|`) and the
  delimiter row's alignments, as pure text with tests, with `MarkdownRenderer`
  setting `paragraph.alignment` from what it says.

The two string passes go in `AbydosKit` rather than beside the renderer, because
`AbydosApp` has no test target and these are exactly the parts worth a test.

## What this does not fix

- **A code span inside a link label** stays plain text inside a working link, as
  it does today. It is not lifted, because `` `x` `` outside the link would stop
  being a link, and a label that *is* a code span would stop being a link
  entirely — a worse bug than the one being fixed.
- **Reference links.** `[a **b**][ref]` is flattened the same way and is left
  alone; the lift handles inline links, which is what the document uses.
- **Images.** `![alt **b**](…)` — Foundation drops images to their alt text
  before any of this, which is its own entry if anybody wants pictures.
- **A table without leading bars.** GFM allows `a | b` with no bar at the line
  start; `splitOutTables` requires one. Not touched here.

---

Its number is where it sits in the queue, not what it is worth doing next.
