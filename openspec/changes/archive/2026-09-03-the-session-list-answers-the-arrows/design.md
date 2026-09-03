## Context

The popover is a filter field above a scroll view around
`RunningSessionsListView`, which draws three kinds of row — a group header, a
session, a footer — and keeps `hovered` for the pointer. The controller is the
field's delegate and answers `insertNewline:` by choosing the first visible
session. Nothing in the list takes the keyboard; `NSView`'s default
`acceptsFirstResponder` is false.

## Goals / Non-Goals

**Goals:**

- Out of the field with ↓, through the rows with ↓ and ↑, into a session with ⏎.
- Back to the field with ↑ from the top, so the movement is reversible.
- Which row ⏎ will open, visible.

**Non-Goals:**

- Type-select in the rows. The field above them is the way to narrow the list,
  and two places to type would be two.
- ⌘↓ / Home / End / Page keys. The list is bounded to a dozen rows on screen
  and scrolls; the arrows reach all of it. A longer list is a different
  problem.
- A selection that outlives the popover. It is transient, opens on the first
  row, and there is nothing to remember: the list is rebuilt from the register
  every time it opens.

## Decisions

**The list takes the keyboard, rather than the field forwarding to it.** A
field that interpreted the arrows and drove a selection elsewhere would leave
the responder in the field, so ⏎ would still be the field's and the rows would
have a selection nobody could see the point of. `acceptsFirstResponder` on the
list, `moveDown:` in the field handing the responder over, and from then on the
keys are the list's.

*Ruled out: making the rows an `NSTableView`.* It would bring the arrows, the
selection drawing and the scrolling for free — and a table is what this list
deliberately is not: three kinds of row, none of them edited, drawn by one
`draw` that reads the theme where it is used. Trading that for the arrows is a
rewrite to gain two keys.

**The selection is an index into the drawn rows, and the arrows skip what is
not a session.** Headers and the footer are rows in the same array; moving by
one and then walking past anything that is not a session keeps one array and
one drawing, and means the arrows cannot land somewhere ⏎ has nothing to do
with.

**A selection and a hover are drawn differently.** The hover tint is
`selectionBackgroundInactive`, which is what it was: a hint about the pointer.
A keyboard selection is `selectionBackground` — the palette's own answer for
"this is the row a key will act on" — so a list with the pointer resting over
one row and the selection on another says which is which.

**↑ from the first row returns to the field with the caret at the end.**
Selecting the whole text instead would mean the next character typed replaces
the filter, which is not what somebody moving back up to add a letter wants.

**Escape from the rows closes the popover**, which is what Escape does from the
field. A first version made it clear the selection instead; two meanings for
one key, and the second is reached by pressing ↑ enough times.

## Risks / Trade-offs

**A reload while a row is selected can move the selection** → The order no
longer depends on time, so a reload puts the same rows in the same places; the
selection is kept by the session's id across a reload and falls back to the
first row when that session has gone.

**The scroll view and a drawn selection** → The list already knows every row's
frame, so scrolling the selected one into view is `scrollToVisible` on that
frame.
