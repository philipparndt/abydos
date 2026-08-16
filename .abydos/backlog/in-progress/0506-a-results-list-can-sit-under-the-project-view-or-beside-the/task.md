# 506. A results list can sit under the project view, or beside the terminals

> it should also be possible to place these lists in the terminal area as well
> as the area between terminal and project view

A usages or search list has two homes today: docked in the bottom panel, and
expanded into a window of its own. `UsagesPane` has one button for it, titled
`Expand` or `Dock` (`UsagesPane.swift:77`), and `spec/usages.md` has the
requirement that the window is remembered.

Two more were asked for, and both were chosen deliberately over a full docking
system:

- **Under the project view** — the left sidebar split horizontally, the tree
  above and the list below. This is the "area between terminal and project
  view", and IntelliJ's left-bottom tool window slot.
- **Beside the terminals** — the list as a tab in the bottom panel's own strip,
  next to the terminal tabs, rather than as a pane of its own.

## The layout as it stands

    splitView          (vertical)   [ navigatorContainer | editor.view ]
    verticalSplitView  (horizontal) [ splitView / bottom panel        ]

`navigatorContainer` holds a single `toolContainer`, and the comment above it
says it *used to be a split and was made one view again*. Whoever does this
should read why before splitting it a second time — the reason it was
simplified is likely to be the reason this is harder than it looks.

## Worth deciding

- **What remembers the placement.** Per project, like the tab layout in 0454,
  or one global preference? A list is opened by an action rather than by being
  restored, so "where does the next usages search appear" is the real question
  and it is not the same as "where is this one now".
- **What the button becomes.** One button that toggles two states cannot choose
  between four. A menu on the button, a drag, or a submenu in the pane's
  context menu — 0455 and 0470 both had this shape of choice and are worth
  reading first.
- **Whether search comes too.** They are the same widget and the spec says so.
  If search cannot go where usages can, the spec has to say why.
- **What happens to the other panes in the bottom strip.** Changes, branches,
  backlog and scratches live there. Moving one list into the strip beside
  terminals raises whether the strip is "terminals plus one guest" or a place
  any pane may sit — the second is the full docking system, which was
  explicitly *not* asked for. Keep the line somewhere defensible and write down
  where.
- **The keyboard.** `spec/usages.md` is emphatic that the list is worked from
  the keyboard and that the keyboard stays in it. Every new home has to keep
  that, including the one where the list is a tab beside a terminal that wants
  every keystroke it can get.

## What was decided, and what was found

The pictures are `images/`: the two new homes for each list, the window, and
the one that shows the state before any of this work.

### The item's second home already existed, as described

**"Beside the terminals — the list as a tab in the bottom panel's own strip,
next to the terminal tabs" is what the docked list has been since item 470.**
`BottomPanel.Session.Kind` has `.usages` and `.search` beside `.terminal`, and
they are all tabs on the same strip.
`images/before-search-was-already-beside-tmux.png` is the app before any of
this work, with a `Search` tab sitting next to a `tmux` tab. Whoever filed this
read the layout diagram and not the running program.

So the item as written asked for a home the program had. Two readings were
open and the second was taken:

1. *The description is right and the work is already done.* This makes the
   user's request — "place these lists in the terminal area" — a request for
   something they were looking at, which is not a reading to take on a request
   somebody troubled to write down.
2. *A tab is not "beside".* A tab is **instead of** a terminal: click the
   terminal and the list is gone. The panel can also hold two **columns**, and
   a list in one with a terminal in the other is beside it in the only sense
   that is not already true. That is the home this item built.

The machinery for the column was there and unreachable for a list: a tab could
be dragged onto an edge (`putBeside`), but nothing routed a results list to it,
and `putBeside` ended with `session.terminal?.focus()`, which for a list is
`nil` — so the keyboard stayed wherever it was, which beside a terminal means
*at the shell*. That is the one real bug this item found rather than added.

### The sidebar comment, and whether its reason still held

It said, in full: the sidebar "used to be a split with a second pane underneath
for a docked view, and the only thing ever docked there was the usages list —
which item 470 moved into the bottom panel beside search… A split with one pane
in it and a divider nobody can reach is not worth keeping for a route nothing
takes."

**The reason was about the route, not about the split, and this item is the
route.** There was no technical difficulty hiding in it — no layout fight, no
autosave collision, nothing about the tree's width constraint. The objection
that stands is the second sentence, and it is answered rather than repeated:
`sidebarSplit` holds exactly one arranged subview until something is docked
below, and an `NSSplitView` with one subview draws no divider at all. There is
nothing to reach until there is something to reach for.

### The five decisions

1. **What remembers a placement: per window, per list, in memory, not on
   disk.** This is item 470's argument for `usagesOpenInWindow` extended from
   two homes to four, and it survives the extension intact: where a list should
   go is the shape of the current job — *this* symbol has two hundred usages and
   the panel is forty rows tall — rather than a preference about the program.
   Ruled out: `Settings`, because one move would then decide how Find Usages
   behaved for months; and `ProjectSession` alongside 0454's tab layout, because
   0454 restores something and this restores nothing — it would be the only
   entry in a session file that is about a list no session ever brings back.

   **One each rather than one between them.** They are the same widget, but they
   are reached by different actions with different rhythms: a search is a
   question being refined and wants to stay where it can be typed at; a usage
   list is a job being walked and wants to be wherever there is room. Somebody
   who sends a 263-row usage list to a window has said nothing about where ⇧⌘F
   should answer, and one shared placement would make them say it.

2. **What the button becomes: a pull-down, where the button was.** `Place`,
   titled with the home the list is in now, listing all four with a tick on the
   current one. Ruled out — **a drag**, because two of the four homes accept no
   drops at all and inventing drop targets in the sidebar and on the desktop for
   one guest *is* the docking system that was declined; and **a submenu on the
   pane's context menu**, because the context menu over the list is the row menu
   (Mark as Done, Mark as Not Done, Hide Rows Marked Done), and putting the
   pane's layout under the same right-click as a row's marking is how somebody
   moves the list when they meant to tick a row.

   The title says where it *is* rather than where it would go. That is the one
   thing the old two-state button got right — "Expand" beside a docked list
   named the next press — and with four destinations there is no single next one
   to name.

3. **Search comes too, all four homes, the same control.** They are one
   checklist and the spec says so; a home usages could reach and search could
   not would be a difference `spec/search.md` had to explain and could not.
   It cost one thing that was not obvious: **search's controls do not fit a
   sidebar.** The first list put under the project view had its query field
   squeezed to the width of the magnifying glass with the toggles on top of it
   . The controls now go on two rows below
   a threshold width — the field above, the options, the `✓`, the count and the
   Place control below. The threshold is a *width* and not a home, because a
   panel dragged down to a third of the window is the same shape and asking
   "which home am I in" would be right about the sidebar and wrong about that.

4. **The line on the strip: placement is a property of the list, not of the
   panel.** The panel and the sidebar each take one guest, by name. Nothing else
   in the program grows a Place control, and no host has to answer "what can I
   hold". The reason this line is defensible rather than arbitrary: a results
   list is the one pane here that is *asked for* rather than opened — Find Usages
   and ⇧⌘F produce one and the only question is where the answer appears —
   whereas changes, branches, the backlog, scratches, a terminal and a debugger
   are all things somebody went to, and they are already where they went.
   The lower half of the sidebar and the window each hold one list; the strip
   holds both, because it already holds everything else.

5. **The keyboard: every arrival ends in `focusList()`, and the column beside a
   terminal is the one that had to be proved.** `UsagesPane`/`SearchPane` gained
   a `window-key:` driver step that sends a key at the **window** so the
   responder chain routes it — the existing `space-key` and friends call
   `tableView.keyDown` directly, which is the right test of what the table does
   with a key and no test at all of whether the key would have reached it. With
   the list in one column and a live `tmux` shell in the other,
   `window-key:down` twice and `window-key:space` moved the selection two rows
   and struck that row through, `who` said `ChecklistTable` before and after,
   and nothing was typed at the prompt.

### Two more places that assumed the panel

- **A maximised terminal hides the sidebar.** The first list sent under the
  project view reported `where=sidebar` over a window containing nothing but a
  terminal: `isPanelMaximized` hides the whole of `splitView`, sidebar and
  editor together. The sidebar route now gives the window back, which is the
  same courtesy `setPanelVisible(true)` does for the panel routes.
- **`findInProject` used to open the panel before deciding anything.** It no
  longer does: the panel is one of four homes now, and opening it for a search
  that is about to appear under the project tree is a panel opening for nothing.

## Steps

- [x] Read the sidebar-split comment and say whether the reason it was
      simplified still holds
- [x] Decide what remembers a placement, and write the answer down
- [x] Four homes named in one place, and one control that chooses between them
- [x] A list can be put under the project view, and the sidebar splits for it
- [x] A list can be put beside the terminals, in a column of the panel rather
      than a tab in its strip
- [x] Moving between all four homes — panel, sidebar, beside, window — keeps the
      rows, the ticks and the selection
- [x] The keyboard still works the list in every home, and a list beside a
      terminal does not lose keys to it
- [x] A driver step that sends a key through the *window* rather than into the
      table, so "the terminal did not take it" is a claim that can fail
- [x] Search moves the same four ways usages does
- [ ] The placement is remembered, by whatever was decided
- [x] Watched in the app, in each home, with a screenshot of each
- [x] Write down here what was ruled out on the way
- [x] `spec/usages.md` and `spec/search.md` say what the project now does

## Estimate

2026-08-16 17:50 — most of a day
