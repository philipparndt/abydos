# Design

## Context

`ChangesPane` is one class at two sizes — the sidebar's cramped form and the
editor page — and `arrangePage` is the page's whole layout. Today it builds a
horizontal split of the file lists and the diff, pins that to the top and both
sides, and hangs a full-width vertical stack of summary, description and commit
row beneath it. The stack's height is fixed by its contents: a 26-point field, a
150-point description, a commit row, two gaps and the insets.

The page also has a divider whose position is set once, in `layout()`, the first
time there is a width — deliberately, because a split that reset itself on every
layout would undo the drag somebody had just made. Anything added to either side
of that split has to live with that rule rather than fight it.

Two constraints come from the repository. Cost is a design constraint, and this
is layout: it runs on every resize of a page somebody drags the divider of. And
the tests reach `AbydosKit` and nothing in `AbydosApp`, so what can be tested
here is whatever can be made a value — which, for a layout, is little. The check
is a driven run and a photograph.

## Goals / Non-Goals

**Goals:**

- The diff keeps the height on a short page.
- The file lists stop losing height to a message that is not about them.
- The description is there when it is wanted and costs a row when it is not.
- The gestures that mean "I am writing more" open it without being taught.

**Non-Goals:**

- The sidebar arrangement. It has its own box and its own `…` to reach the page,
  and the reported fault is the page's.
- Remembering the chevron across sessions. It is a page that opens, is typed in
  and is closed; a preference for it would outlive the reason it was set.
- Making the description resizable by dragging. A splitter for a field that is
  usually empty is more chrome than the field.
- Anything about what a commit is, what may be amended, or when Push lights up.

## Decisions

### The message goes inside the split, under the diff

The right-hand side of the split becomes a vertical stack of the diff and the
message; the left-hand side stays the two file lists and runs the full height.

The message is about what is staged, and so is the diff — the file lists are how
you choose what to look at. Putting the message under the diff also makes the
divider mean one thing: everything to the right of it is the commit being
written, and dragging it gives the message width along with the diff.

*Ruled out: keeping the message full-width and shrinking it.* It is the smaller
change and it leaves the file lists paying for a message that is not theirs. The
capture shows both faults at once, and fixing the height alone would leave the
tree cut off at ten rows on a page that has room for twenty.

*Ruled out: the message as a third pane of the split, with its own divider.*
Three panes to drag on a page whose divider is already placed once and then left
alone, for a field that is usually one line.

### The description is collapsed by default, and always starts that way

Not "collapsed when the page is short". The rule is the same at every height.

A layout that changes shape as the divider moves is one nobody can predict: the
description would appear and disappear while dragging, and the height at which it
did would be a number nobody knows. The same page every time is easier to learn
than a page that is cleverer than you.

What the short page needed was the height back, and collapsing by default gives
that at every size — while the chevron, remembered for the page's lifetime, costs
somebody who writes long messages one click per page rather than one per commit.

*Ruled out: collapsing below a height threshold.* Above it is a magic number, and
below it the page rearranges itself under the pointer.

*Ruled out: starting expanded and collapsing when unused.* A field that vanishes
while you are looking at it is worse than one you have to open.

### The gestures that open it are the ones that already mean "more"

Return at the end of the summary, and a draft arriving with a description.

Return in a single-line field ends editing today, and it is what somebody presses
when they have finished the subject and mean to keep writing — the same reflex as
a mail client.

**The commit key moves, and this design first said it would not.** The button
carried plain `\r` with no modifier, so taking Return for the description would
have left the page with no keyboard commit at all. It carries ⌘Return now, which
is what a page with a text area on it means by "commit" everywhere else, and
which works from the description as well — where Return has always been a
newline. The push button takes the same modifier, since `updateCommitButton`
swaps `\r` between the two and a swap would otherwise hand Return back.

A draft is the one moment the description fills without anybody typing in it, and
leaving it behind a chevron would hide work that has just been done. `ClaudeDraft`
already fills both fields; it now reveals the second.

*Ruled out: opening on focus.* Tabbing through the page would open it, which is
not a request to write a paragraph.

### Collapsing is a constraint being turned off, not a view being removed

The description keeps its place in the stack and its 150-point height constraint
is deactivated, with the view hidden. `NSStackView` collapses a hidden arranged
subview, so the stack shortens by exactly the box and its gap.

*Ruled out: removing and re-adding the view.* The text has to survive the
chevron — collapsing a description somebody typed and losing it would be the
worst version of this — and a view that is only hidden keeps it without anything
having to be saved and put back.

### The chevron is beside the summary, on the leading edge

It reads as belonging to the field it opens, and the summary row already has a
control on the other end — the Draft button — so the two do not collide.

*Ruled out: a disclosure triangle above the box, the way an inspector section
does.* That is a row of chrome of its own, which is what this change is removing.

## Risks / Trade-offs

- **Somebody who always writes a description now clicks once per page** → the
  chevron is remembered for the page's lifetime, and Return at the end of the
  summary opens it without reaching for the mouse at all.
- **The diff column is narrower than the page** — the message now lives in it →
  it is the same width the diff already had, and the divider moves both.
- **A collapsed description that has text in it looks empty** → it cannot be
  collapsed with text in it: the draft opens it, and typing into it means it was
  open. The one path that could produce it — collapsing by hand after typing — is
  somebody choosing to put their own text away, and the chevron they used is the
  way back.
- **The page's divider is placed once, in `layout()`** → unchanged. What moves is
  what hangs off the right-hand side of it, and the rule that the position is set
  once and then left to the person dragging it is not touched.

## Open Questions

- Whether the chevron should carry a hint that there is text behind it when
  collapsed — a dot, or the first few words. Not decided: the case it serves
  exists only for somebody who collapsed their own writing, and a summary of a
  summary is the kind of thing that reads well in a design and badly on screen.
- Whether ⌘Return should also open the description when it commits nothing — a
  commit refused for an empty summary currently just does nothing.
