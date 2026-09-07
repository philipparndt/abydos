## Context

See `proposal.md` — Why. What matters here is the shape of the view this lands
in.

`DiffView` (`Sources/AbydosApp/Git/DiffView.swift`, 1,044 lines) is hand-drawn,
like `CodeView` and the terminal: a `GitPatch` is flattened into `rows` — a
header, a scope rule, a hunk header, a line, a pair of lines side by side, or a
row of somebody's remark — and `draw(_:)` lays out only the rows in the dirty
rectangle. That is what keeps a lockfile's diff instant to open, and it is the
constraint every decision below is made under.

It already has a *selection*: `selection: Set<Int>`, indices into `GitPatch`'s
flat line numbering, filled by a drag over the rows and read by *Stage Selected
Lines*, *Discard Selected Lines*, *Stash* and *Comment on Lines*. There is no
caret, no `NSTextView`, no `NSPasteboard` and no `copy(_:)` anywhere in the
file.

One view serves five places — the pull request page, the commit page, the
history pane, the changes pane and the editor's diff tab — so this is written
once and arrives everywhere. The changes pane is the only one that can stage,
and `isReadOnly` is how it is told apart.

The Edit menu's *Copy* is already `NSText.copy(_:)` with ⌘C and no target
(`AppDelegate.swift:2798`), so it walks the responder chain: a `copy(_:)` on the
view is the whole of the keyboard plumbing.

Tests are `Tests/AbydosKitTests` only — there is no view test target, and
`DiffView` cannot be instantiated without a window. Behaviour that is to be
claimed in a test has to be reachable from `AbydosKit`, and behaviour that is
not is claimed by a driven run.

## Goals / Non-Goals

**Goals:**

- One selection model over `rows`, so the geometry code has one idea of where a
  character is and drawing, hit-testing and copying cannot disagree.
- A cost proportional to what is on screen for drawing and to the rows selected
  for copying — never to the size of the diff.
- The line selection keeps working exactly as it does, from its new gesture.

**Non-Goals:**

- A caret, editing, or anything that makes this an editor. There is one, in the
  next tab.
- Find-in-diff, and a selection that survives the diff being rebuilt (see
  Decisions).
- Any change to `GitPatch`. The text is already in it.

## Decisions

### A position is a row and an offset within that row's text, not a document offset

`TextPoint { row: Int, offset: Int }`, ordered by row then offset; the selection
is an ordered pair of them. Offsets are UTF-16, because that is what Core Text
answers in and what `NSAttributedString` is indexed by.

*Why not a document offset,* the way `CodeView` holds one over its rope: there
is no document here. `rows` is derived, and it is rebuilt when the arrangement
changes, when the chrome preference changes, when a remark is written and when
the whole-file switch is thrown — a single offset would have to be remapped
through every one of those, and each remapping would be a place to be subtly
wrong about which line somebody had selected.

**A rebuild drops the text selection**, as `setDiff` already drops the line
selection. Turning on side by side with three lines selected therefore loses
them. The alternative is remapping a selection across an arrangement that
splits one row into two halves, which cannot be done correctly for a selection
that spanned rows; losing it is honest and the gesture costs a second to
repeat.

### Hit-testing and highlight geometry come from Core Text, not from a column width

For a row, the same attributed string that draws it is measured with
`CTLineCreateWithAttributedString`; `CTLineGetStringIndexForPosition` turns an x
into an offset and `CTLineGetOffsetForStringIndex` turns an offset back into an
x for the highlight.

*Why not the terminal's arithmetic* — `column = (x - inset) / cellWidth` — which
would be cheaper: the terminal draws a grid and this does not. A row here is a
marker of *measured* width followed by text, hunk headers are drawn in the bold
face, a remark is prefixed with ✍️ or 💬, and the code contains tabs and the
occasional glyph the monospace face does not have and a fallback supplies. Every
one of those puts the arithmetic's answer a few pixels — and eventually a
character — away from where the glyph is. That is the terminal's own old bug, and
there is no reason to import it.

`CTLine`s are built for the rows a gesture touches and the rows being drawn, and
cached by row index behind the same invalidation as `rows` — dropped on rebuild,
on a theme change and on a font change. Drawing already builds an attributed
string per visible row, so the highlight adds no pass the frame did not have.

### One place says what a row's text is

`func text(of row: Row) -> String`, and `func textOrigin(of row: Row) -> CGFloat`
beside it, used by drawing, hit-testing and copying alike.

`text(of:)` is where the proposal's *no furniture* rule lives: a line gives
`line.text` and not its marker, a pair gives the side's `line.text`, a hunk
header and a scope rule give what they show, and a remark gives its text without
the emoji. The marker is drawn separately at `textX` today and the origin
already accounts for it; factoring that expression out of `draw(row:)` is what
stops the highlight from being drawn one marker-width away from the glyphs it is
meant to be behind.

### Two selections, mutually exclusive, last gesture wins

`text: TextSelection?` beside the existing `selection: Set<Int>`. Setting either
clears the other, and `copy(_:)` prefers the text one.

*Why not one selection* that the menu interprets: a run of lines and a run of
characters are different things — one is a set of `GitPatch` indices with a
`+`/`-` meaning, the other a pair of points — and *Stage Selected Lines* over
half a word is not a command. Keeping them apart also means the staging path is
untouched: the only thing that changes for it is which pixels fill the set.

### Where the press landed decides which selection it makes

`region(at:) -> Region` — `.numbers(row)`, `.text(row: Int, side: Side)`, or
`.header(row)` — from the same x boundaries the drawing uses:
`horizontalInset + gutterWidth + numberWidth * 2` unified, and the same offsets
inside each half side by side. The marker column belongs to `.text` at offset 0;
a press there selects nothing until the drag moves, which is what a press on any
text does.

Side by side, the `Side` in `.text` is carried through the drag, which is how
"a selection belongs to one side" is enforced rather than checked afterwards.

### Copying reads `rows`, not the layout

`copiedText` walks the rows the selection covers, takes `text(of:)` for each,
cuts the first and last by their offsets and joins with `\n`. No `CTLine` is
built and nothing off-screen is laid out, so ⌘A then ⌘C over a five-thousand-row
diff costs a string join.

### The copyable text is a value type in AbydosKit, so it can be claimed in a test

`DiffTextSpan` in `Sources/AbydosKit/Git/` — two points, an array of row texts,
and the string they produce. `DiffView` hands it the rows it has and asks.

*Why there and not in the view:* there is no view test target, and "what does
this selection copy" is the half of this change most likely to be quietly wrong
— off-by-one at a row boundary, a reversed pair, an empty row in the middle, a
selection that ends at offset 0 of a row. That is a table of cases and belongs
in `Tests/AbydosKitTests`. It carries no geometry, no `NSView` and no `AppKit`,
so it does not break the rule that keeps view code out of the engine.

### Autoscroll during a drag

`autoscroll(with:)` in `mouseDragged`. A selection that stops at the bottom of
the visible rows is a selection that cannot cover a hunk, and the view is
already inside an `NSScrollView` in all five places.

### `selectAll` changes meaning; nothing else calls it

`selectAll(_:)` selects every stageable line today, and nothing outside the file
invokes it — no menu item targets it and no driven run reaches it. It becomes
select-all-text, which is what ⌘A means in every other view in this window.
Staging everything is still the file row's *Stage*, and a hunk is still its
header.

### A driven run reads back what would be copied and does not write the clipboard

`copiedTextForTesting` returns the string; a separate
`copyToPasteboardForTesting` writes it, and only a step that asks for it by name
calls that. This is the tree's arrangement
(`ProjectNavigatorViewController.copyTextForTesting`) and the reason is the
house rule about the machine somebody is using: a driven run that clobbers the
general pasteboard on every capture takes away whatever they had copied.

New `--pull-requests` steps: `text:12.4-14.9` (row.offset to row.offset, against
the diff on screen) and `copy`, which prints what the clipboard would hold.

## Risks / Trade-offs

- **The staging drag moves, and somebody's hand knows the old one.** → The two
  gestures that do most of the staging do not move at all: the hunk header, and
  *Stage* on the file. The new one is where a forge puts it, and the numbers are
  a 60-point-wide target beside the code rather than a 14-point gutter.
- **`CTLine` per touched row could be built per `mouseDragged`.** → Cached by
  row index; a drag over forty rows builds forty lines once and then reads them.
  Measured as part of the work: a drag down a 5,000-row diff must not be slower
  than a scroll of it, and `MachineLoad.said` goes beside any number that is
  claimed.
- **A selection lost to a rebuild reads as a bug.** → It is the same rule the
  line selection already follows, and the rebuilds that do it are all gestures
  somebody just made (arrange, whole file, write a remark), never something
  arriving on its own.
- **Emoji and tabs put the highlight and the glyphs in different places.** → The
  reason Core Text does both halves. The check is a diff with a tab-indented
  line, a line with an emoji in a string literal, and a remark, selected end to
  end and photographed.
- **`copy(_:)` on a view inside a page that also has a list with its own
  keyboard.** → `validateMenuItem` answers only when the diff is the first
  responder, so ⌘C in the file list still copies what the list copies.

## Open Questions

- Whether a selection should be drawn while the diff is *not* the first
  responder at all in the changes pane, where the two trees above it take the
  keyboard constantly. The spec says unfocused-grey, which is what the editor
  does; if it reads as noise in that pane it becomes a `hasKeyboard`-only
  highlight there. Either answer is a colour, and neither moves a requirement.
