## Context

The rail is `ToolWindowBar`, one `StripButton` per tool, in two stacks: the
sidebar tools at the top and, below a separator, `[backlogButton, reviewButton,
debugButton, terminalButton]` — the panes that dock under the editor.

What is on disk today:

    setSidebarSelection(visible:tool:)   six sidebar buttons, one rule, correct
    setTerminalSelected(_:)              called only from setPanelVisible
    setDebugRunning(_:)                  a debug session is running
    backlogButton.isSelected             never written
    reviewButton.isSelected              never written

`StripButton.draw` already separates the two things this needs. The fill behind
the icon is drawn for `isSelected` (and, fainter, for hover); the icon's colour
is `accent ?? (isSelected ? sidebarHeaderText : sidebarText)`. So an accent
colour and a selection are already composable, and the rail already uses the
combination — `updateCommitButton` sets `accent` to `Theme.current.gitModified`
for uncommitted work and `Theme.current.gitAdded`, the green, for work not
pushed.

The panel is `BottomPanel`, holding `Session`s whose `kind` is one of `terminal`,
`review`, `search`, `usages`, `backlog`, `debug`, `profiler`. **It can be split
into columns**: `activeByColumn` keeps one active session per column and
`activeSession` is the focused column's. So "which tab is in front" is not always
one answer.

The only existing announcement of a change is `onActiveTerminalChanged`, raised
from `refreshTabs()` and subscribed to by `TerminalWindowController`.

## Goals / Non-Goals

**Goals:**

- The rail says which pane is in front, with one meaning of the fill.
- The backlog button behaves like every other button in its group.
- A debug session running is still visible with the panel closed, and is now
  distinguishable from the debug tab merely being in front.
- Nothing changes for the sidebar group, which is already right.

**Non-Goals:**

- A rule for the panel's own tab strip, which already says which tab is in front.
- Lighting a button for a pane kind that has no button — `search`, `usages` and
  `profiler` open in the panel and are reached from elsewhere.
- Any new drawing in `StripButton`.

## Decisions

**One rule for the bottom group, and it is the sidebar's rule.** The top of the
rail already answers "what is on screen rather than what was last picked", and
that sentence is as true of the panel as of the sidebar. Adopting it means the
fill means one thing everywhere on the rail, which is what makes the picture in
the report readable at all.

Ruled out: lighting the backlog alone. It is the smallest change and it makes
the rail worse — the backlog and the terminal would both be lit with the backlog
in front, so the rail would answer one question twice.

Ruled out: leaving the terminal meaning "the panel is open". That is a real
thing somebody might want to know, but it is not what the other three buttons in
the group say, and a group of four where one is answering a different question
is exactly the state being fixed. The panel being open is already visible: the
panel is on screen.

**The panel is asked which kinds are in front, not which session.** The rail has
one button per *kind*, the panel can be split, and two kinds can be in front at
once — a terminal on the left and the backlog on the right is an ordinary
arrangement. So the question the panel answers is a set of kinds, one per column,
and the rail lights every button in it. Ruled out: asking only the focused
column, which would put the fill on whichever half was last clicked and take it
off a pane that is plainly on screen.

**The debug button is lit for either reason, and green for one of them.** Keeping
`isSelected` as the union means nothing is lost when the panel is closed, which
is the whole point of `setDebugRunning`. Colouring the running case green makes
the two tellable apart without a second visual language: the rail already reads
blue and green on the commit button for two things it has to say at once, and
`Theme.current.gitAdded` is the green it already uses.

Ruled out: replacing "running" with "selected". It would take away the signal
`setDebugRunning`'s comment exists to explain — that something is being debugged
while the panel is shut — and nothing else on screen says it.

Ruled out: a badge or a dot. The strip is thirty points wide and a dot on a
sixteen-point glyph is a smudge; the icon's own colour is the room there is.

**Green is `Theme.current.gitAdded` and not a new colour.** A theme that has been
given a palette has already answered "what green does this theme use", and a
second green chosen here would be right in the default theme and wrong in
somebody's.

**How the rail is told.** The panel raises a change when the set of front kinds
changes, and the window passes it to the rail — the same shape as
`setSidebarSelection`, which the window already calls. `onActiveTerminalChanged`
is the existing hook and is now named for a narrower question than it answers;
whether to rename it or add a second is left to the building, and it is the sort
of thing that should be one hook rather than two.

**The panel closing lights nothing**, which follows from the rule and is worth
stating because it is a behaviour change for the terminal button: today closing
the panel unlights it, and after this it unlights every button in the group.

## Risks / Trade-offs

- **A pane kind with no button leaves the group unlit.** Opening a search or a
  usages pane puts nothing on the rail, which reads as "nothing is in front"
  rather than "this one has no button". → True today as well, and the honest
  alternative is a button for every pane kind, which is a different change about
  a rail that is thirty points wide.

- **Green may read as "good" rather than "running".** The commit button's green
  means "work not pushed", which is not a compliment either, so the rail is at
  least consistent with itself. → Worth looking at once it is drawn; the accent
  is one line to change.

- **The union on the debug button hides a state.** A debug tab in front *and* a
  session running looks the same as a session running with the tab in front of
  nothing. → They are the same button doing the same job and the tooltip is where
  a difference that fine belongs.

## Open Questions

- **Whether `onActiveTerminalChanged` should be renamed or joined by a second
  hook.** It is raised from `refreshTabs()` and has one subscriber; the answer
  depends on whether the new question fires at the same moments, which is a thing
  to find out while wiring it rather than to guess at here.

- **Whether the review button should follow its pane or its menu.** The review
  button opens a *menu* of two scopes rather than a pane directly, so "lit while
  a review is in front" is right for the pane and says nothing about the menu
  being open. Taken as the pane, since that is what the other three do.
