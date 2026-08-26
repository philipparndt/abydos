## Context

`BranchesPane.build()` lays out four things above the outline: an inset, an
`NSSearchField`, a half-inset, a row holding `New Branch…` and the traffic
button, a half-inset, then the scroll view. Removing them is easy. The three
decisions worth making are where the traffic state goes, how a row comes to have
a button, and how that button is reached without a mouse.

The pane is already an `NSOutlineView` over a mixed row model — `Row` is an enum
with cases for the working copy, a side, a change, a branch, a stash, a stash
file. Adding a repository case is the shape the file is already in.

## Goals / Non-Goals

**Goals:**

- Nothing above the outline. The pane is a list from its top edge.
- The traffic state readable without hovering, scrolling or opening anything.
- Commit visible, and named after what pressing it does.
- One row-action affordance, not three buttons wired separately.

**Non-Goals:**

- Changing what fetch, pull and push do, or the pull dialog. `git-remote-traffic`
  is untouched; only where the control is drawn moves.
- Changing what filtering does once it is open.
- Row actions on stash and remote rows. The affordance is built so they can have
  them; giving them any is a change of its own.

## Decisions

### The repository row is pinned, and pinned means a second outline of one row

`NSOutlineView` has no sticky row. The two ways to get one are a floating group
row — `NSTableView`'s `floatsGroupRows`, which pins a *section header* while its
section is on screen and lets it go when the next section arrives, which is not
what is wanted — or a second view above the scroll view holding exactly that row.

So: a one-row outline above the scrolling one, sharing the row model, the row
view, the metrics and the theme with it. It is not a header in the sense being
removed — it is a row of the tree that happens not to scroll, drawn by the same
code as the rest, and it carries no controls of its own.

*Alternative considered:* let it scroll with everything else. Rejected in the
spec for the reason the traffic button exists at all — how far you are from the
remote is state, and a repository with forty branches puts it off screen
immediately.

*Consequence:* the pane is 24 points shorter than "no chrome at all", not 58.
The saving is 34 points, and the row that costs those 24 is showing information
the header only had room to abbreviate to `↓3 ↑1`.

### A row action is a rect in the row, not a subview

Rows here are custom-drawn — `RowMetrics.draw` places text and counts in a
`draw(_:)`. A trailing action gets the same treatment: a rect computed at draw
time, stored on the row view, drawn when the row has an action and the pane
knows it should show one, and hit-tested in `mouseDown` before the row's own
default gesture.

This is how the tab bar's trailing controls already work — `previewButtonFrame`,
`overflowButtonFrame`, checked in `mouseDown` before the tabs, because the
control sits over them. Following it means one pattern for "a control drawn into
a custom row" rather than a second one.

*Alternative considered:* an `NSButton` subview per row. Rejected — outline rows
are recycled, so buttons have to be attached and detached as rows scroll, and
the pane already draws everything else by hand.

### When an action shows

The repository row's action is always shown: it is the state, and hiding it
behind a hover would hide the state. The working copy's is shown whenever the
count is non-zero, for the same reason — it is the everyday act and the point of
this change is that it stops being hidden. `LOCAL`'s `+` shows on hover and on
selection, because making a branch is occasional and the row is a section label
that should stay quiet.

Selection counts as hover for this purpose, which is what makes the keyboard
work: the row you have arrowed to shows what it offers.

### The keyboard gesture is `⌘⏎`

`⏎` is taken on a branch row — it checks the branch out — and overloading it
would make the same key mean two things on two rows.

`⌘⏎` fires the selected row's action. On the repository row it pulls; on the
working copy it opens the commit view; on `LOCAL` it makes a branch; on a branch
row it does nothing, because that row's verbs are its context menu's. Everything
`⌘⏎` reaches is also in the row's context menu, which stays the place where
things are named rather than shaped.

*Alternative considered:* `→` on a row with no children. Rejected — `→` expands,
and the tree's rows mostly have children; a key that expands here and acts there
is the overload again.

### The filter is the find bar, not a field

`⌘F` while the pane has the keyboard shows a filter strip over the list, with
the keyboard in it, closing on `esc` and when emptied. It is not the editor's
find bar object, but it behaves as one, because that is the gesture already in
the hands using this app.

The pane keeps its filter *state* exactly as now; only how the text gets there
changes. That keeps `Filtering flattens the tree` true without touching the code
that implements it.

## Risks / Trade-offs

**A pinned row is a second outline, and two outlines can disagree.** → They share
one row model and one draw path; the pinned one is given the repository row and
nothing else, and has no selection of its own. A driven check reads both.

**The traffic state gets longer.** `↓3 ↑1` became `3 behind · 1 ahead`, and the
pane can be 250 points wide. → The row abbreviates the way every other row here
does, and the tooltip already carries the long form. Worth watching in the
driven screenshots at a narrow width.

**Hover-only affordances are invisible.** → Which is why only `LOCAL`'s is
hover-only, why selection counts as hover, and why `⌘⏎` and the context menus
cover everything.

**`⌘F` may be claimed by something else when the pane has the keyboard.** → It
is the editor's find today; the pane taking it while focused is the same
arrangement the terminal has for its own keys. Checked with the menu-key report,
which exists for exactly this.

## Migration Plan

Four commits, each green and each leaving the pane usable:

1. The row action affordance, with `LOCAL`'s `+` as its first user.
2. The working copy's `Review N change…`, and the renaming in the menu and the
   shortcut.
3. The repository row, pinned, taking the traffic control; the button goes.
4. `⌘F`; the field goes.

Nothing is removed before its replacement works, so the pane never has less than
it has today.

## Open Questions

- Whether the repository row should also carry the branch's own verbs — push,
  pull, the upstream it tracks — or only the traffic state. It draws the branch,
  so the rule says it could; the risk is a row that is a menu.
- Whether `⌘⏎` should fall through to the context menu's first item on rows with
  no action, or do nothing. Doing nothing is the assumption.
- What the repository row shows for a repository whose upstream is gone — not
  level, not behind, not ahead. `GitPush.state` answers it and the wording is a
  question for whoever writes that row.
