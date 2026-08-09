# 431. A markdown table loses bold in a link, bold after a tilde, and its alignment

A shopping list — a GFM pipe table whose delimiter row is `|---|---|---|---:|`
— renders three things wrong in the preview pane, and they were reported as
three bugs. Two of them turn out to be one bug wearing two coats, and the third
is the only one that is honestly ours. A fourth was found while looking.

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
4. **Found while looking: `\|` in a cell splits the row.** "Kantenband \|
   gerollt" became two cells, every column after it slid one to the right, and
   the whole table grew a fifth column that nothing was in.

## Whose parser this is

`Sources/AbydosApp/Editor/MarkdownRenderer.swift`, and it is **half ours**.
Blocks and inlines come from Foundation's `AttributedString(markdown:)` — which
is cmark-gfm behind an `AttributedString` — and everything about tables is hand
written on top of it, because Foundation's parser does not understand pipe
tables at all and hands them back as paragraphs with bars in them.

So the split matters: **1 and 2 are inside Foundation, 3 and 4 are inside
ours**, and no amount of using Foundation more carefully fixes 1 or 2. Both were
measured against the parser on its own, with no table, no pane and no window
anywhere near them:

    "[a **b** c](https://x.com)"  ->  "a b c"{link}
    "**~ 211 EUR**"               ->  "**~ 211 EUR**"

## 1. Foundation flattens a link's label

Every inline construct inside a link label is parsed, its markers are removed,
and the resulting attribute is thrown away. Measured: `**`, `*`, a code span and
`~~` inside a label all come back as one plain run carrying nothing but the
link. It is not the walk in this file missing a child — there is no child in
what Foundation returns, only a single flat run.

The reverse works: `**[b](https://x.com)**` gives a run that is both bold and a
link. That is the way out, and it is the fix.

## 2. It is not the last cell. It is the tilde.

The report guessed the row splitter was handing the final cell over unparsed, or
swallowing the trailing `|`. **Both are wrong**, and worth writing down so
nobody looks there again: the splitter is fine, and position has nothing to do
with it. The construct fails in the *first* cell, in a paragraph, in a heading,
with no table in the document at all. `**Summe**` works in the last cell.

What fails is exactly one shape — a tilde **directly against the opening
delimiter** that can only close a strikethrough:

    fails                       works
    **~ 211**                   **~211**      the tilde can open, so it is no closer
    *~ 211*                     **a ~ b**     spaces both sides: not a delimiter at all
    ***~ a***                   **a~ b**      a closer, but not against the opener
    __~ a__                     **(~ a)**     one character away is already enough
    **~ **                      **~**         nothing after it to be a closer for

CommonMark's flanking rules say why a tilde is a closer here: preceded by
punctuation (the `*`) and followed by whitespace makes it right-flanking and not
left-flanking, so GFM's strikethrough extension pushes it on the delimiter stack
as something that can only close. It closes nothing, and the emphasis it is
standing in front of dies with it. **Why adjacency is what matters is not
visible from outside** — the obvious explanation, that cmark records a lower
bound at the opener, is contradicted by `**a b~ c**` staying bold, and this is a
shipped binary. The measurement is the thing; the table above is the whole of
what is known.

**This is a defect in the shipped cmark-gfm, not a use of it.** The parsing
options were exhausted — `.full` and `.inlineOnlyPreservingWhitespace` behave
the same, `allowsExtendedAttributes` is already on, and there is no option that
turns the strikethrough extension off.

## 3. Alignment was not read, and 4. bars were not counted

- **Parsed?** No. `renderTable` said in a comment that row 1 "carries alignment,
  not content" and then dropped it on the floor.
- **Expressible?** Yes, and cheaply. The table is a real `NSTextTable`, each
  cell already builds an `NSMutableParagraphStyle` that it stamps over the whole
  cell, and `paragraph.alignment` is one line in the place that style is built.

And the row splitter was `body.components(separatedBy: "|")`, which cannot tell
a column boundary from a bar somebody wants to see.

## What was done

**Not a different renderer.** Swapping Foundation for tree-sitter-markdown — the
grammar is already a dependency, for colouring the *source* — would mean writing
the whole block and inline walk by hand, several hundred lines, to fix two
inline bugs, and would put the preview's correctness on a grammar chosen for
highlighting. That is the owner's call and was not made while fixing three bugs.

Instead, one pre-pass over the **copy of the source handed to the parser** —
never anybody's file, never the text in the editor — plus the table work:

- **`MarkdownSource.liftedLinkEmphasis`**: `[a **b** c](url)` becomes
  `[a ](url)**[b](url)**[ c](url)`. Emphasis around a link survives, so the
  markers move outside; adjacent links to the same destination come back as
  neighbouring runs, so what the pane is given is what should have come out of
  the parser. The label is re-emitted from *Foundation's own reading of it*
  rather than from the markers in the source, which is how nesting
  (`***b***`) and entities come out right for free.
- **`MarkdownSource.escapedStrayTildes`**: an unmatched right-flanking `~`
  becomes `\~`, which parses as the same character and is not a delimiter. Runs
  are paired first, so `~~struck~~` and `~struck~` are untouched. It escapes a
  little more than the one failing shape, on purpose: the pairing is a rule
  anybody can check, and "directly against an opener" is a rule about a bug.
- **`MarkdownTable`** in the kit: the row splitter honouring `\|`, the delimiter
  row's alignments, and telling a delimiter row from a paragraph that begins
  with a bar. `MarkdownRenderer` sets `paragraph.alignment` from what it says.

The two string passes are in `AbydosKit` rather than beside the renderer,
because `AbydosApp` has no test target and these are exactly the parts worth a
test. Eighteen of them, in `MarkdownPreviewTests`, asserting what comes back out
of Foundation rather than what the repair wrote — a test on the repair's own
output would only say that it agrees with itself.

### How much of anybody's markdown this touches

Measured, because a pass that rewrites source before parsing it has to be shown
to leave things alone: over the **431 markdown files in this repository** —
README, `docs/`, and four hundred backlog entries — the repair changes **one**,
the fixture, in exactly the three places it is meant to.

Getting there took one more piece of work than expected. The first version put a
`\~` into *this entry*, inside the indented block quoting `"**~ 211**"` as the
bug it is about. An indented block is a quotation and the inline parser never
looks at it, so `protectedMask` learnt about four-space blocks as well as fences
and code spans — and about the fact that four spaces under a list item is a
paragraph belonging to the item rather than code.

## What the neighbours came to

The three faults suggested a class rather than a coincidence, so the rest of the
class was checked. All of these are tests now.

- **Emphasis inside a heading, a list item, a blockquote** — fine before and
  after. Foundation splits those into runs correctly; only link labels are
  flattened.
- **A link with emphasis inside a heading, a list item, a blockquote** — was
  broken everywhere, for the same reason, and is fixed everywhere by the same
  pass.
- **Code spans in table cells** — fine. They render as code because a cell is
  parsed as markdown in its own right.
- **A code span inside a link label** — still plain text inside a working link.
  Deliberate; see below.
- **An escaped `\|` in a cell** — was broken, is fault 4 above, fixed.
- **The first cell as well as the last** — no positional bug exists. Both were
  measured, and `**Summe**` in the last cell was always bold.

## What this does not fix

- **A code span inside a link label** stays plain text inside a working link.
  It is not lifted, because `` `x` `` outside the link would stop being a link,
  and a label that *is* a code span would stop being a link entirely — a worse
  bug than the one being fixed.
- **Reference links.** `[a **b**][ref]` is flattened the same way and is left
  alone; the lift handles inline links, which is what the document uses.
- **Images.** `![alt **b**](…)` — Foundation drops images to their alt text
  before any of this, which is its own entry if anybody wants pictures.
- **A table without leading bars.** GFM allows `a | b` with no bar at the line
  start; `splitOutTables` still requires one.
- **A link split across a line break.** The lift scans for `](` on one line.

---

Its number is where it sits in the queue, not what it is worth doing next.
