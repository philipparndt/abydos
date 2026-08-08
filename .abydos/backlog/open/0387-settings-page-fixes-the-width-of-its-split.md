# 387. The settings page fixes the width of the split it is in

Settings opened as a tab in a split editor cannot be widened: the divider will
not move while it is showing. Widening the split first and then navigating to
Settings snaps it back, squeezing the editor tab beside it.

So the page is imposing a width rather than fitting what it is given — a
minimum width, a fixed content width, or a hugging priority that beats the
divider. It should be the other way round: the split decides and the page lays
out inside it, scrolling when there is not room.

Whatever the page does must not undo a divider somebody has set, and coming
back to a tab should never move a divider at all.

`SettingsPage` and `SettingsWindowController.appearanceRows` build the
content; the tab lives in the editor's split, so `EditorAreas` and
`PreviewSplitView` are where the constraint is honoured or ignored.

**From reading, not yet from measuring** — the width most likely comes from the
scroll view rather than from anything that looks like a width:

    clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
    clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

Pinned on both sides, the document view is exactly as wide as the clip view, so
the content can never be narrower than what it needs — and what it needs is
real: a 260-wide text field, 190-wide pop-ups, a 200-wide slider, inside a card
whose own width constraint is only a cap (`.defaultHigh`, `equalTo`
form.width) and not a floor. That fitting width leaves the scroll view, leaves
the page, and reaches the split. Somebody has already fought this once:
`sidebar` and `scroll` both have their compression resistance lowered to
`.defaultLow - 1`, which lowers the priority of the fight without ending it.

The splits are in mixed mode, which is why it can bite at all: a view moved by
`EditorAreaController.split` gets `translatesAutoresizingMaskIntoConstraints =
true`, while the new group beside it is added as an arranged subview under
autolayout, and `NSSplitView` honours a fitting width where it finds one.

So the change to try is to stop the page imposing that width: trailing pinned
with `>=` plus a low-priority `==`, and a horizontal scroller, so a page too
wide for its pane scrolls instead of widening it. Worth measuring
`SettingsPage().fittingSize.width` before and after — the app has no test
target, so that measurement has to be printed from a debug run rather than
asserted.

---

Numbered 56 while it was being worked on, which is what a
commit message citing it means.
