## Context

`RunningSessionsController` is the filter field above the scrolling
`RunningSessionsListView`, with `onChoose`, `onEscape` and `onResize` as its
seams. It is used as an `NSPopover`'s content, anchored to the pill by
`PanelRunningSessions.show(from:of:)`. That presenter also owns what a row does
— the reach, the reveal, the resume command — and the clock that keeps the
counts honest.

`SymbolPalette` is the app's existing answer for a keyboard-opened list: an
`NSPanel` with `[.titled, .fullSizeContentView]`, a hidden title, a transparent
title bar, centred near the top of the parent window and added as its child,
put away by Escape or by losing key.

The titlebar capsule draws `⇧⌘P` beside the project's name, dimmed: the app's
own way of saying "there is a key for this".

## Goals / Non-Goals

**Goals:**

- The list one key away, with the panel closed.
- One list, two hosts.
- The key discoverable from the route people find first.

**Non-Goals:**

- Centring on the *screen*. See the decision below.
- A second shortcut for the pill's popover. The pill is the pointer route and
  the key is the keyboard route; two keys for one list would be one too many.
- Moving the pill. It says what is running from across the room, which the
  palette cannot do because it is not on screen.

## Decisions

**The palette is centred over the window, not the screen.** The request said
"like Spotlight", which is a screen-centred panel — and this app is not
Spotlight: it has more than one window, often on more than one display, and the
list is opened from a window by a key that window answered. A screen-centred
panel would appear away from the window that opened it whenever the window is
not on the main display. `SymbolPalette` settled this for the same reason, and
this follows it rather than inventing a second geometry.

**The controller is reused, not copied.** It was written with `onChoose`,
`onEscape` and `onResize` as its only outward edges, so a second host is those
three closures and a window. Copying the filter and the rows would be two lists
that drift — and the arrows, the selection and the spinner all live in the
view, so a copy starts a turn behind.

*Ruled out: making the popover a palette and dropping the pill's popover.* The
popover explains the pill: it opens where the counts are and points at them. A
palette in its place would answer a click on the pill by appearing somewhere
else on screen.

**The presenter owns both.** `PanelRunningSessions` already knows how to build
the list and what a row does; the palette is a second `show`. Putting the
palette in the window controller instead would mean a second place that knows
about the reach, the resume command and the register.

**The popover advertises the key and the palette does not.** Somebody in the
palette pressed the key to get there. The label goes at the trailing edge of
the filter row, dimmed, in the shape the capsule uses — not in the footer,
where the two sentences already there would crowd it and where the eye does not
land when the list opens.

## Risks / Trade-offs

**A palette and a popover can both be open** → Opening one closes the other:
the presenter holds both and puts the other away, since they are one list and
two of it is a bug that would be reported as a duplicate. Closing a popover is
not instant — `close()` animates, and it stays `isShown` for about a fifth of a
second, which the driven run caught as "open in both". The swap turns the
animation off and drops the reference, so the other route is gone before this
one appears.

**⇧⌘A with a text field focused** → It is a menu key equivalent, so the menu
takes it before the field sees it, which is what every other ⇧⌘ verb in this app
does.

**The palette over a window that is not the key window** → It is opened by a
menu action on the key window's controller, so there is exactly one candidate.
