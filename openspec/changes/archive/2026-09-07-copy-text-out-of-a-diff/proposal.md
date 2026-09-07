# Copy text out of a diff

## Why

A pull request's changed files are read in `DiffView`, and nothing in it can be
selected as text. Dragging over the code selects whole *lines* — the gesture
that stages a line in the changes pane and picks the run a remark is left on —
so a hand that arrives wanting a variable name, an error message or the three
lines a reply is about comes away with a highlighted row and an empty
clipboard. ⌘C over the diff does nothing at all: `DiffView` has 1,044 lines and
not one mention of `NSPasteboard`.

This is what a reader concludes from it, in the words this was raised in: *"this
files appear to be just some kind of preview"*. That is the fault — a view of
real code, drawn from a real patch, that behaves like a picture of one. Every
other place code is shown in this window can be selected and copied: the editor
(`CodeView`), the terminal, the hex view. The diff is the exception, and it is
the one place a reviewer spends a whole afternoon.

It bites hardest where it was noticed. Reviewing means quoting: pasting the line
under discussion into the remark, pasting an identifier into the search field to
see what else calls it, pasting a stack frame into a terminal. Today each of
those means finding the file again in the editor — which is only possible at all
because the branch was checked out — and finding the line again there.

There is no originating `.abydos/backlog` item; the backlog was retired before
this was raised.

## What Changes

**A diff's text is selected by dragging over it.** Character by character,
across rows, in both arrangements — unified and side by side — drawn as a text
selection is drawn everywhere else in this window: behind the glyphs, in the
theme's selection colour, grey while the keyboard is elsewhere.

**⌘C copies it, and so does *Copy* at the top of the menu.** With no text
selection but a run of lines selected, ⌘C copies those lines, because a
selection that is visibly there and copies nothing is the same complaint again.

**What is copied is the code, not the diff.** No line numbers, no `+`/`-`
marker, no gutter — what a forge's rendered diff gives, and what makes the two
arrangements copy the same characters. A selection over several rows joins them
with newlines.

**Selecting whole lines moves to the line-number column.** A press or drag over
the numbers takes lines, the way a forge does it; a click on a hunk header still
takes the whole hunk, which is how most staging is actually done. **BREAKING**
for one gesture: dragging over the *text* of the changes pane's diff no longer
selects lines to stage.

**⌘A selects all the text**, and the diff becomes something the Edit menu's
*Copy* is enabled over — the standard responder path, so a diff answers ⌘C the
way every other view does rather than through a shortcut of its own.

**Double-click takes a word, triple-click takes the row**, because a reader who
has just learnt the drag works will try both within the minute.

**A remark is copyable too.** Existing review comments are rows of this view and
their text selects like any other, so answering a reviewer can quote them.

## Capabilities

### New Capabilities
- `diff-selection`: what a gesture in a diff selects — text by character over
  the code, whole lines over the numbers — what the selection is drawn as, and
  what it copies.

### Modified Capabilities

None. `openspec/specs/version-control` names *Discard Selected Lines* once, to
say where it is hidden; it never says how a line comes to be selected, and no
other spec does either. So the gesture that moves is unspecified today and this
adds a capability rather than changing one — the same reading
`openspec/changes/terminal-selection` made of the terminal's spec. What *is*
offered over a line selection, and where it is hidden, stays exactly as
`version-control` describes it.

## Impact

- `Sources/AbydosApp/Git/DiffView.swift` — a text selection beside the line
  selection it already has, hit-testing from a point to a row and an offset
  within that row's text, the highlight, `copy(_:)`, and `validateMenuItem`.
- Every diff in the window, since there is one `DiffView`: the pull request
  page, the commit page, the history pane, the changes pane and the editor's
  diff tab. That is the point — a fix in one place, and no arrangement of a
  second diff view to disagree with it.
- Hit-testing is Core Text against the row's attributed string rather than a
  column measured off the font: the row is drawn with a marker of measured
  width, syntax colours over it, tabs in the code and the occasional glyph the
  monospace font does not have, and a selection that lands where the glyphs are
  not drawn is the terminal's old bug arriving here.
- Only the rows on screen are laid out today, and copying needs the text of rows
  that are not. The text comes from `GitPatch` rather than from anything the
  drawing built, so a selection over a five-thousand-line diff costs the rows it
  covers and not the diff.
- `--pull-requests` gains steps that select text and read back what would be
  copied, so the claim is checkable in a driven run rather than by hand.
- **Not in scope**: editing the diff, a caret in it, find-in-diff, and opening
  the file the diff is of into an editor tab — the pull request page already
  checks the branch out for that.
