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

## Steps

- [x] `OpenFile` carries the preview mode, and an absent one means the default
      for that file kind
- [ ] `restore(_:)` puts the mode back, and the divider with it, after layout
- [x] A mode is ignored for a file that has no preview
- [ ] Seen by eye: a `.scad` in Split Right, a project switch, and back
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
