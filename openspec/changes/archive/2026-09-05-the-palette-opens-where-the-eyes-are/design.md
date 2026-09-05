## Context

`ProjectSwitcherPopover.show` builds a `SwitcherViewController` — the ranked
list of projects, branches and actions, its filter field and its key handling
— and puts it in an `NSPopover` anchored to a view the caller hands it: the
project pill for ⇧⌘P and for a click on the pill, the branch pill for a
branch list, the run control for the run list.

`RunningSessionsPalette` solved the same problem the other way when ⇧⌘A was
added: the popover's controller, unchanged, in a `PalettePanel` placed
centred horizontally on the parent window and 120 points down from its top,
made a child of that window. Its comment says why the window and not the
screen: this app has more than one window and often more than one display, and
the list is opened *by* a window. `SymbolPalette` had settled it that way
first.

So the pieces exist; what is missing is that ⇧⌘P asks for the click's
geometry.

## Goals / Non-Goals

**Goals:**

- One placement rule for every list a key opens: centred on the window that
  answered the key, near its top.
- The same list, the same controller, the same keys, whichever window is
  around it.
- A driven run able to say where it landed, as ⇧⌘A's already can.

**Non-Goals:**

- Not changing what the switcher lists, ranks or does when a row is chosen.
- Not moving a click's popover off the control that was clicked.
- Not a second controller, and not a second palette window class.

## Decisions

### The caller says which it wants, and the popover keeps both

`show` gains the caller's intent — anchored to a view, or centred over a
window — rather than a second entry point that duplicates the controller
setup. The key path builds a `PalettePanel` exactly as
`RunningSessionsPalette` does (theme, Escape, close on resign-key, child of
the parent window) and places it with the same arithmetic; the click path is
untouched.

*Ruled out:* always centring — the pill's own click would then open a list in
the middle of the window, away from the control that was pressed, which is
the mistake this change is undoing in the other direction.
*Ruled out:* a `RunningSessionsPalette`-shaped copy for the switcher — two
placements copied into two files is how the two drift; the placement is small
enough to share and is already written twice.

### The key that opened it closes it

`PalettePanel` closes on Escape and on losing key. ⇧⌘P pressed again while the
panel is up closes it, the way ⇧⌘A's panel handles its own key — a child
window's responder chain does not run through its parent, so the menu item is
disabled while the panel is key and the keystroke arrives at the panel.

## Risks / Trade-offs

- [Two placements of the same list, so two things to keep looking the same] →
  one `show`, one controller, and the placement arithmetic shared with the
  palette that already has it rather than copied.
- [A window narrower than the list] → the existing arithmetic already keeps
  the panel inside the parent's frame, which is why it is the one to share.
- [Muscle memory for a corner popover] → the request is the muscle memory
  saying otherwise, and a click on the pill still opens it at the pill.

## Open Questions

None: ⇧⌘A names the geometry, and the click names the exception.
