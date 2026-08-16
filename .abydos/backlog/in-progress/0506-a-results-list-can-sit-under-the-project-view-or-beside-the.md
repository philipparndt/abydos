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

## Steps

- [ ] Read the sidebar-split comment and say whether the reason it was
      simplified still holds
- [ ] Decide what remembers a placement, and write the answer down
- [ ] Four homes named in one place, and one control that chooses between them
- [ ] A list can be put under the project view, and the sidebar splits for it
- [ ] A list can be put beside the terminals, in a column of the panel rather
      than a tab in its strip
- [ ] Moving between all four homes — panel, sidebar, beside, window — keeps the
      rows, the ticks and the selection
- [ ] The keyboard still works the list in every home, and a list beside a
      terminal does not lose keys to it
- [ ] A driver step that sends a key through the *window* rather than into the
      table, so "the terminal did not take it" is a claim that can fail
- [ ] Search moves the same four ways usages does
- [ ] The placement is remembered, by whatever was decided
- [ ] Watched in the app, in each home, with a screenshot of each
- [ ] Write down here what was ruled out on the way
- [ ] `spec/usages.md` and `spec/search.md` say what the project now does

## Estimate

2026-08-16 17:50 — most of a day
