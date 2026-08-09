# 421. The settings page will not stay the width it is dragged to

Settings open in a group beside an editor. The divider can be dragged, the page
follows it — and on releasing the mouse it snaps back to where it was. There is
a width it will not go past, and it returns to it.

This is the third time this page's width has been a bug. 0399 was the same
family: the page's own constraints reached the split it sits in, so a settings
tab could not be made narrower and widening the split and coming back snapped it
shut again. That was fixed by making the content's trailing edge `>=` the
viewport with a low-priority `==` beside it, which is still there and still
right — so this is something else, and the fix is not to loosen those again.

**What was ruled out by reading, before running out of session:**

- `PreviewSplitView` is not obviously it. It preserves the *proportion* across a
  resize of the split itself, allows a pane down to `scaled(48)`, and collapses
  nothing. Nothing in it runs at the end of a drag.
- `SettingsPage.build()` still has the 0399 shape: `clip.trailing >=
  contentView.trailing` required, `==` at `defaultLow`, and each block pinned to
  `form.width - scaled(56)` at `defaultHigh`.

**Where to look, in order.** The snap happens on mouse-up, so something is
setting the position *after* the drag rather than constraining it during one —
`adjustSubviews`, a `setPosition`, or a stored fraction being reapplied by
whatever owns the editor groups. Find who owns the split that holds two editor
groups; it is not `PreviewSplitView` unless that class is used for both.

The likely shape, from the fact that there is a width it will not pass: a
constraint at `required` somewhere in the page still wins over the drag, and
AppKit re-runs layout after the mouse goes up. `defaultHigh` on the blocks is
above `defaultLow`, so the low-priority `==` on the clip cannot be what holds
it; look for a `widthAnchor` with no priority set, which is `required`.

**Reproduce:** open settings, drag it into a group beside an editor, drag the
divider wider, release. A screenshot cannot show this — it needs a live drag,
which is why it was not measured here.

## Also: Tools should collapse

`SettingsSections.flattened` renders parents and children as one flat list, and
`SettingsPage.indent(forRow:)` draws the depth. Tools has eight children, which
is most of the sidebar, and there is no way to fold them away.

The list is an `NSTableView` over a flattened array, so collapsing is a filter
on that array plus a disclosure triangle in the parent's row — not an
`NSOutlineView`, unless somebody wants one for other reasons. Worth deciding
whether the state is remembered between launches; the sections are few enough
that reopening collapsed might be more surprising than helpful.

---

Its number is where it sits in the queue, not what it is worth doing next.
