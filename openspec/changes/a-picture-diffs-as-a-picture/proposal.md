## Why

A changed picture in the commit page, the log page or a pull request diffs as
the one line **No textual changes.** — git says the file is binary, the patch
has no hunks, and the diff view draws the sentence it draws for a patch with
nothing in it. That is true and useless: a screenshot in the documentation was
re-taken, an icon was redrawn, a diagram's export moved a box, and the only
way to see what changed is to open both versions elsewhere and look between
them. The app already opens a picture as a picture, on a checkerboard, fitted
to its pane (the `previews` capability); a diff of one should be no less.

Asked for on 2026-09-03: "the git diff (e.g. during commit) shall support
graphical changes by showing left/right, a slider, changed regions; the user
can switch between those modes."

There is no originating `.abydos/backlog` item.

## What Changes

- **A changed picture diffs as two pictures.** Wherever a diff is shown — the
  commit page for a working-copy or staged change, the log page for a commit,
  the pull-request page for a fetched commit — a file the app recognises as a
  picture is shown as its two sides read from git rather than as the sentence.
  Added and deleted pictures have one side, and say so.
- **Three ways of looking, and a switch between them.** *Side by side*: the
  old picture on the left and the new on the right at one scale, each labelled
  with what it is and its pixel size. *Slider*: the two drawn over each other
  at one scale with a divider that is dragged left and right, the old side
  showing to its left and the new to its right. *Changes*: the new picture
  with the regions that differ from the old drawn as outlined rectangles and
  the rest dimmed, with a count of them. The switch is the library's choice
  control above the pictures, and the mode chosen is remembered as a setting.
- **The regions are arithmetic, in AbydosKit, tested without a window.** Two
  pictures of one size are compared pixel by pixel above a small threshold; the
  differing pixels are gathered into rectangles. Pictures of different sizes
  have no regions and say so, and the other two modes still work for them.
- The text diff is unchanged for everything that is not a picture.

## Capabilities

### New Capabilities

- `picture-diffs`: what a changed picture shows wherever a diff is shown — the
  two sides, the three modes, the switch, the regions, the one-sided cases and
  the sizes that cannot be compared.

### Modified Capabilities

None. `previews` says how one picture opens; this is what two of them do in a
diff, and it is its own subject.

## Impact

- **AbydosKit**: `GitRepository` gains a way to read a blob as bytes, since
  `ProcessResult` carries text; `PictureDiff` compares two bitmaps and yields
  regions; `FilePreview.kind` already says what a picture is and is reused.
- **AbydosApp**: a `PictureDiffView` beside `DiffView`, hosted by the same
  three panes, which choose it when the change is a picture; a `DrawnChoice`
  for the mode; a setting for the mode chosen. `ImageFileView`'s checkerboard
  and fitting are the model, not the code — that view owns one picture and a
  zoom, and this owns two and a comparison.
- **Driver**: the diff report says which view is up, the mode, the two sizes
  and the region count; a step switches the mode; a screenshot shows each.
- **Cost**: two blob reads and one pixel comparison per selection of a picture,
  off the main thread, as the text diff's parse already is. A comparison of two
  4k screenshots is a few million pixel reads and well under the time the text
  parse is allowed.
