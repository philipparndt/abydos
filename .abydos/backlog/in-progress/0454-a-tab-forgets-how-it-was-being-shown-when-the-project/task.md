# 454. A tab forgets how it was being shown when the project changes

Open a `.scad` file, put it in Split Right so the model is beside the source,
switch to another project and come back: it is the source only. The same for
Markdown, PlantUML, Mermaid, draw.io and anything else with a preview.

## Why

`EditorViewController.captureSession()` writes three things per tab:

    ProjectSession.OpenFile(path:, line:, isPreview:)

`path` and `line` come back. `isPreview` is the *provisional tab* flag — the
italic one a single click opens — and has nothing to do with the preview pane,
which is a name collision worth being careful about while working here.

**`PreviewMode` is not captured at all.** It has four cases — `source`,
`preview`, `splitRight`, `splitDown` — and every tab falls back to the default
when a session is restored. Switching project is exactly the moment the whole
tab set is rebuilt, so it is where this shows; the same loss happens on relaunch.

## What to build

`OpenFile` carries the mode, and `restore(_:)` puts it back. That is most of it.

Three things to get right rather than assume:

- **The divider.** A split with the mode remembered but the divider at its
  default is still not the tab somebody left — and a divider is a fraction of a
  pane that has not been laid out yet at restore time. `5edc084` already records
  what happens when a divider is set before layout: it is computed against the
  old geometry and lands in the wrong place.
- **An old session has no mode.** Absent must mean "the default for this file
  kind", not `source`, or every tab anybody has open today comes back wrong once
  and blames the change.
- **A file whose kind cannot preview.** A `.swift` tab with `splitRight` written
  against it should not try; the mode is only meaningful where
  `FilePreview` says there is something to show.

## Worth deciding

Whether the mode belongs to the **tab** or to the **file kind**. Remembering it
per tab is what was asked for and is the smaller change. But somebody who always
wants `.scad` split and Markdown previewed is asking for a preference, and the
per-tab memory would keep answering it correctly by accident until the day they
open a `.scad` they have never opened before. Say which this is, and leave the
other for whoever wants it.

## Decided: per tab

The mode belongs to the tab. It is written in the session beside the path, the
line and the provisional-tab flag, and it says nothing about `.scad` files in
general — a `.scad` opened for the first time still opens as its kind's default,
which for a script with a source worth reading is the source.

That is the smaller change and it is the one that was asked for, but it is also
the one that can be told apart from the other by looking at it. A preference
would be a fifth answer somewhere in Settings — "always split a `.scad`" — and
what makes it a different feature rather than a bigger version of this one is
that it has to apply to a file *nobody has opened yet*. The per-tab memory
cannot: it has nothing to say about a file it has never seen. Left for whoever
wants it, and it fits on top of this without disturbing it, because
`FilePreview.defaultMode(for:)` is already the one place the kind decides and a
preference would go there.

## What was found on the way

- **`isPreview` really is the other thing.** The session file now has `preview`
  and `mode` a line apart meaning the provisional tab and the pane. Both names
  were already in use before either knew about the other; renaming one is a
  session-file migration for a word, so they are left alone and the collision is
  written down instead — in `OpenFile`, in `SessionStore` and here.

- **The divider was not one line of the fix but most of it.** The old code
  deferred `setPosition(total / 2)` by a runloop turn and guarded on `total > 0`
  — which quietly meant "only the tab in front gets a divider at all". A split
  built for any tab behind it measured zero, gave up, and was saved by luck:
  `adjustSubviews` had already left the two panes equal, which is what the line
  was asking for. Restoring a fraction that is not a half made that visible, so
  the fraction is now kept on the split view and spent at its first layout with
  room in it. The tab in front is no longer a special case.

- **Ruled out: setting the position from `restore`, deferred.** The same shape as
  the code being replaced, and it fails the same way for a tab that is not in
  front — there is no runloop turn after which an unlaid-out view has a size. It
  also has nowhere to keep the answer for the tab somebody clicks a minute later.

- **Ruled out: applying it from `splitView(_:resizeSubviewsWithOldSize:)`.** That
  delegate does run when the split first gets a size, but it is also the method
  that preserves proportions on every window resize, and a pending fraction there
  competes with the proportion it is being asked to keep. `layout()` is the one
  place that means "you have a geometry now".

- **Guarded, and 5edc084's overflow is the reason.** `setPosition` lays the split
  out again synchronously, from inside `layout()`. The pending fraction is
  cleared *before* the call rather than after, which is what makes the re-entry
  return immediately. The other guard is a floor: a fraction spent on a pane a
  few points wide is clamped to the minimum pane by the split's own delegate, and
  a later resize keeps whatever proportion it finds — so one transient layout
  would have been permanent.

- **Not proved by hand: a divider moved with the mouse.** There is no launch flag
  that drags the *preview* split — `--editor-divider` drags the split between
  editor groups, which is a different view. What was proved is the state a drag
  leaves behind: a split sitting at 0.75 was read back out of its own frames as
  0.75 and written to the session, which is the same code path with the same
  input.

## Steps

- [x] `OpenFile` carries the preview mode, and an absent one means the default
      for that file kind
- [x] `restore(_:)` puts the mode back, and the divider with it, after layout
- [x] A mode is ignored for a file that has no preview
- [x] Seen by eye: a `.scad` in Split Right, a project switch, and back —
      `images/scad-split-right-after-a-project-switch.png`, with the divider at
      0.75 to tell a restored split from a default one. Markdown in Split Down
      at 0.35 came back the same way, and a session with no modes in it brought
      the `.scad` back as source and the `.mmd` back split, which is each kind's
      own default
- [x] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
