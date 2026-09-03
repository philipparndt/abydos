## Context

`RunningSessionsListView` holds `rows` — headers, sessions and a footer in one
array — and two `Int?`s into it: `selected`, which the arrows and ⏎ act on, and
`hovered`, which the pointer sets. `reload` rebuilds `rows` from the register and
was already re-finding `selected` by id; it kept `hovered` as it was, only
clearing it when it ran off the end.

`PanelRunningSessions` reloads whichever host is open once a second while
anything is working, and on every hook event.

The popover is built fresh each time the pill is clicked. The palette is not: it
keeps its window and its controller, which is what makes it remember — and what
makes `viewDidAppear` fire for the first opening only.

## Goals / Non-Goals

**Goals:**

- Neither lit row moves unless the thing it is about moves.
- A remembered selection that says what it is.
- ⏎ that does what the highlight says.

**Non-Goals:**

- Forgetting the selection between openings. It was called nice, and it is:
  reopening a list to carry on where you left off is the point of remembering.
- Freezing the list while it is open. The counts and the states are why it is
  worth looking at; a row is allowed to move when its *session* moves.

## Decisions

**Re-found, not renumbered.** The alternative is to keep the numbers and fix
them up when the rows change — which is the bug, written once more with an
adjustment: it needs to know what changed, and the array it is given is new.
Asking "which row holds this id" and "which row is the pointer over" needs no
history at all.

**The hover comes from the window, not from the last event.** `mouseMoved`
arrives only when the pointer moves. After a rebuild there has been no event, so
the hover has to be asked of `mouseLocationOutsideOfEventStream` — the pointer's
position now rather than where it last was when something happened.

**A ring for the remembered selection, rather than a second fill.** The theme
offers an inactive selection colour, and using it here would put the unfocused
selection at the same weight as the hover tint — two states that are visible at
the same time, constantly. An outline is a different shape rather than a
different shade, so it survives any palette and cannot be mistaken for the
pointer's own hint.

*Ruled out: giving the rows the keyboard on reopening.* It would make the
highlight honest and take away typing, which is what the field is for and how
the list is meant to be used.

**⏎ follows the highlight.** With a selection restored and drawn, "⏎ chooses the
first row shown" is a second answer to the same key. Nothing is lost: with no
selection the first row is what ⏎ still takes.

## Risks / Trade-offs

**A row can still move under the pointer** → When a session appears above it,
the hover follows the pointer to whatever is now under it, which is what a
pointer means. The list is not frozen and should not be.

**The ring is one more state to draw** → Three appearances for three states:
filled bright where the keys are, a ring where the memory is, a faint fill where
the pointer is. They are only ambiguous in pairs that cannot occur.
