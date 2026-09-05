## Context

`StyledTip` is already the app's tooltip: a shared borderless panel at
`.popUpMenu` level, a child of the window that asks, ignoring the mouse,
appearing half a second after the pointer settles, drawn from a `Tip` of
title, optional detail and optional shortcut, and reporting itself as
`reportForTesting` so a driven run can read the words without a screenshot.
`PanelTabStrip` is its only caller: it tracks a `hoveredControl`, draws a
rounded ground under it, and asks the tip for a rectangle in its own
coordinates.

The three places the request names are each shaped differently. The left rail
(`ToolWindowBar`) is a stack of button views, each drawing its own hover from
an `isHovered` flag and carrying an AppKit `toolTip` string. The navigator
header (`NavigatorHeaderView`) is three `NSButton`s with `toolTip` strings, no
tracking areas and no drawn ground. `RunControl` is one view that draws
several rectangles — run, debug, the debug menu's chevron, the scheme and the
status — and registers `addToolTip` rectangles for them, keeping the strings
in a dictionary keyed by tag; it has no hover state at all.

## Goals / Non-Goals

**Goals:**

- One tooltip in the window: the drawn one, in the theme's type, from one
  `Tip` value per control.
- A ground under the pointer on every chrome control that acts when clicked,
  drawn the way the strip and the rail already draw it.
- The words checkable in a driven run, per control, without a screenshot.

**Non-Goals:**

- Not touching the rail's hover, which the request says is right.
- Not putting tips on rows, cells, fields or list items — those are text
  somebody can read, and `toolTip` on a row is a different job (the git panes
  put a path there, and it stays).
- Not moving, renaming or re-grouping any control.
- Not a new tooltip window, a new delay, or a per-view timer.

## Decisions

### One small owner beside `StyledTip`, so a view with several controls repeats nothing

`PanelTabStrip` earns its tip plumbing over eight controls: a `hoveredControl`
enum, a hit test, `updateHover`, the show on change, the hide on exit, and the
rectangle in view coordinates. Three more views would be three more copies of
that, and the third copy is where they start to differ.

So a `TipHost` (a small class a view owns, or a protocol with a default
implementation over a stored table) holds `[(NSRect, Tip)]` for the view,
answers `tip(at:)`, and owns the show/hide calls; the view keeps only what it
already had — which rectangle is hovered, and drawing the ground.
`PanelTabStrip` moves onto it rather than keeping its own copy, so there is
one implementation and the strip stays the reference.

*Ruled out:* a `TipButton` subclass of `NSButton` — it fits the navigator
header and neither of the other two, because the rail's buttons are already a
bespoke view and `RunControl` has no button objects at all, only rectangles.
*Ruled out:* leaving `NSView.toolTip` where a control is an `NSButton` and
drawing tips only where it is not — that is the split this change exists to
remove, and it is visible: two tooltips, two typefaces, in one window.

### The words, and where they come from

A `Tip` per control, written where the control is made, with the shortcut
where one exists — Run's ⌃R and Debug's ⌃D come from the same place the menu
takes them so the two cannot drift, and a control with no key passes none. The
existing strings are kept where they are already right ("Collapse all",
"Select the file in the editor", "Compact middle packages", "Choose what to
run"), gaining a detail line only where the current string was doing two jobs
at once.

### The ground, and what draws it

The tint the rail and the strip already use for a hovered control, at the same
corner radius, drawn by the view that owns the rectangle — `RunControl` draws
its own, the navigator header draws behind its three buttons (which are
`imageOnly` and borderless, so a ground behind them is the only thing that can
show). A control that is *on* — the header's compact-packages pill — keeps its
own on-tint, and the hover must be visible against it, as the sessions pill's
already must be.

*Ruled out:* `NSButton`'s own highlight — it is a pressed state, not a hover,
and it does not exist for `RunControl`'s rectangles at all.

## Risks / Trade-offs

- [Moving `PanelTabStrip` onto the shared owner risks the strip that is the
  reference] → its own driven verbs (`hoverTrailingForTesting`, which returns
  the lit state and the tip's report in one answer) already exist and go
  green before and after.
- [Tips appearing where the pointer merely crosses] → the half-second delay
  and the drop-on-change are `StyledTip`'s already, and are the reason a
  crossing leaves no trail.
- [A tip under a control at the top of the window] → `StyledTip` already flips
  above the control where there is no room below.
- [Three more views asking for a tracking area] → one each, with
  `.inVisibleRect` as the existing ones use, and a hover state that is a
  single enum per view rather than a flag per control.

## Open Questions

None: the request names the areas, the strip names the shape, and the rail
names the hover that is already right.
