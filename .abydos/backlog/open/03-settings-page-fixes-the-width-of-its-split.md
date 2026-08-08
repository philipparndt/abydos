# 3. The settings page fixes the width of the split it is in

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

---

Numbered 56 while it was being worked on, which is what a
commit message citing it means.
