## Context

**What is drawn today.** `CodeView.drawInlineValues` asks
`InlineValues.hints(in:from:)` for a line's hints, joins them with three spaces
and draws the lot as one attributed string past the glyphs, truncating at the
view's edge. Nothing records where any one of them ended up, and nothing needs
to: drawing is all that happens to them.

**What a hint carries.** `InlineValueSet` is a file, a line and
`[String: String]` — a name and the value's text. `DebugSession.selectFrame`
builds it with `InlineValues.byName(scopes)`, which throws everything else about
a `Variable` away. `Variable` itself has what is missing: `variablesReference`,
non-zero exactly when the adapter can be asked for children, which is what
`isExpandable` means.

**What the panel already does with that.** `DebugPane` holds an `NSOutlineView`
over `ScopeNode`/`VariableNode`, and `shouldExpandItem` calls
`session.toggleExpansion(scopeIndex:path:)`, which fetches the children once, on
first expansion, and raises `onVariablesChanged`. The indices in that path are
positions in `scopes`, so they mean nothing to anything that is not that tree.

**Popovers here.** `NSPopover` is used by the project switcher, and the
completion list is a window of its own. Both exist; neither is a component this
can reuse without deciding which one this is.

## Goals / Non-Goals

**Goals:**

- A struct, a pointer or a slice beside the code can be read without leaving the
  line.
- What can be opened looks different from what cannot, before it is clicked.
- Children arrive on the gesture, never on a repaint.
- One tree, in the sense that the panel and the popup behave the same way about
  expanding, formatting and lazy children.

**Non-Goals:**

- Editing values, watching expressions, or anything that writes.
- Changing what is drawn on the line, or how much of it.
- A second copy of the variables tree's row drawing.
- Following the value as execution moves: the popup is about a moment.

## Decisions

**A hint becomes a rect, and the rect is recorded while drawing.** The hints are
drawn as one string today; per-hint geometry is what a click needs. The
arithmetic is already there — the grid is monospaced and each hint's width is
`(name = value).count * charWidth` — so this is recording what the draw already
knows rather than measuring anything new. Kept per drawn row and thrown away
with the next repaint, which is also what makes it correct while scrolling.

**Only the adapter decides what can be opened.** `variablesReference > 0`, which
is `Variable.isExpandable`, and nothing else — not the length of the value, not
whether it starts with a brace, not the type name. Delve says `*net/http.ServeMux`
is a container and `"local"` is not, and reading the string to guess would be the
same mistake as reading a diagnostic's message to guess whether it is true.

**`InlineValueSet` carries `Variable`s.** `[String: String]` cannot say whether
there is anything to open. The map becomes `[String: Variable]`, which is what
`InlineValues.byName` had in its hands before it threw it away — the value text
still comes from `variable.value`, so the drawing is unchanged, and the reference
travels with it.

**The popup is a window of its own, not an `NSPopover`.** A popover is dismissed
by the next click anywhere, which is exactly the gesture somebody makes when
reaching into a tree to expand a row; the completion list is a panel for that
reason. It follows the same rules: it appears at the hint, it is dismissed by
Escape or by clicking outside it, it never takes the keyboard from the editor
except while it is being walked, and it goes when execution resumes — a tree of
values from a program that is running again is the worst thing this could leave
on screen.

**The popup's tree is the panel's tree, factored out.** Two outline views over
the same `Variable` shape, with two ideas about lazy children and two row
drawings, would drift in a week — the notice button and the file notice are the
same story, and that was three lines of duplication rather than a hundred. What
moves is the data source and the row, not `DebugPane` itself.

**Expansion inside the popup goes through the session, not around it.**
`toggleExpansion(scopeIndex:path:)` is addressed by position in `scopes`, which
a popup opened from a name does not have. Either the popup resolves its variable
to that path when it opens, or the session grows a way to expand a variable by
reference. The second is smaller and does not depend on the popup and the panel
agreeing about indices — but it is a second path into the same fetching, so the
first is worth trying first. **Decided in the work**, and written down there.

**Nothing is fetched to draw a hint.** The reference is already in the frame's
answer; opening is a `variables` request made from a click. This is the same
rule the inline values were built on — no `evaluate`, nothing per line, nothing
per repaint — and it is what keeps a stopped editor usable.

## Risks / Trade-offs

- **A click in the editor now does something new.** → Only over a hint, only
  while stopped, and only where the adapter said there are children; everywhere
  else the click still moves the caret, because the hit test runs before nothing
  else changes.
- **The popup covers the code it came from.** → It opens below the line it
  belongs to where there is room and above it where there is not, which is what
  the completion list does about the same problem.
- **A huge container** — a slice of ten thousand — arrives as ten thousand rows.
  → The adapter supports paging on `variables`, and this does not: the first
  page is what a popup shows. Named, not solved.
- **A value that changes while the popup is open** — stepping with it up. → It
  goes when execution resumes, so what it shows is always from one stop.

## Open Questions

- **Can it be opened without a mouse?** A hint under the caret with a key would
  be the honest answer, and there is no obvious key. Left out; the gesture in the
  report is a click.
- **Should the popup be resizable, and should it remember its size?** The
  completion list is neither.
- **Does a leaf hint want anything on click at all** — copying the value, say?
  Doing nothing is defensible and is what this proposes.
