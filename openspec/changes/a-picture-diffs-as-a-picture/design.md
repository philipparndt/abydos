## Context

Three panes host a `DiffView` in a scroll view: `ChangesPane.showDiff(of:)`
fetches `GitWorkingCopy.diff` for a working-copy or staged change,
`HistoryPane` fetches `GitHistory.diff(of:path:in:)` for a commit, and
`PullRequestPage.show(file:)` takes the forge's patch text. All three hand the
text to `DiffView.prepareOffMain` and then `setDiff`. A binary change parses to
a patch with no hunks, and `setDiff` draws "No textual changes."

`FilePreview.kind(for:)` returns `.image` for the extensions the editor opens
as pictures. `ImageFileView` draws one picture fitted to its pane on a
checkerboard, with its own zoom. `GitRepository.run` returns stdout as a
`String`, which is why nothing reads a blob as bytes yet; `GitHistory.contents`
is the text form of the same `git show <rev>:<path>`.

## Goals / Non-Goals

**Goals:**

- A changed picture is seen as pictures in every pane that shows a diff.
- Three modes, one switch, the choice remembered.
- The regions computed by code that tests can call on two bitmaps.

**Non-Goals:**

- A zoom of its own on the diff. Both pictures fit the pane; a closer look is
  the editor's picture view, one click away on the file. If fitting is not
  enough that is the next report, not this change.
- Diffing pictures inside other files — a PDF's page, an SVG's rendering. An
  SVG is text and diffs as text; the picture it draws is a preview question.
- A pull-request change whose commits are not fetched. The forge's API can
  hand over a blob, but that is a second source for the same bytes and this
  change reads them from git or says it cannot.
- Perceptual comparison — colour-space aware, anti-aliasing tolerant. A fixed
  small threshold on channel difference catches what people mean by "changed"
  and misses nothing they would call unchanged; a smarter measure can replace
  it behind the same function.

## Decisions

**The pane chooses the view; the diff view does not grow a mode.** Each host
already knows the file and the two revisions. Where `FilePreview.kind(for:)`
says `.image`, the host reads the two blobs and shows a `PictureDiffView` in
the scroll view's place; otherwise it does what it does. `DiffView` is at its
length ceiling and is about lines; a picture is not a case of a line.

*Ruled out: teaching `DiffView` to draw a picture as a row.* Its rows are
virtualised text with one colour each; a row several hundred points tall with
a draggable divider in it is a different view wearing its clothes.

**The two sides come from git as bytes.** `GitRepository.runData` returns
stdout as `Data`, beside `run`; `GitBlob.read(rev, path)` is `git show
<rev>:<path>` through it. The commit page's *old* side is `HEAD:<path>` for an
unstaged change and the index — `:<path>` — for a staged one; its *new* side
is the working file for unstaged and `:<path>` for staged. The log page's
sides are `<hash>~:<path>` and `<hash>:<path>`, with the rename followed the way
its text diff already follows it. The pull-request page's are the base and
head commits when both are local, and otherwise the view says which side it
could not read.

*Ruled out: reading the working file for the new side of a staged change.*
The staged bytes are what will be committed; the working file may already be
something else.

**`PictureDiff` is arithmetic on two bitmaps.** Both pictures are drawn into
8-bit RGBA bitmaps of their own pixel size; where the sizes match, a pixel
differs when any channel differs by more than the threshold (16 of 255, so a
re-encode's rounding is not a change and a real edit is). Differing pixels are
gathered into rectangles: a grid of 16-pixel cells is marked, marked cells are
joined into connected components, and each component's bounding box is a
region. Regions are what people mean by "what changed"; per-pixel speckle is
not. Sizes that do not match yield no regions and a reason.

*Ruled out: exact per-pixel outlines.* A screenshot's re-taken shadow is ten
thousand pixels that differ by one; boxes over cells say "here" without
drawing every one of them.

**Three modes, one canvas class.** `PictureDiffView` holds the two images,
their sizes and the regions, a `DrawnChoice` with *Side by side*, *Slider*,
*Changes*, and a canvas that draws whichever mode is chosen at one scale — the
scale that fits the wider picture, so the two sides line up. Side by side
draws both with a gap and a label each: what it is (*HEAD*, *staged*, *working
copy*, a short hash) and its pixel size. Slider draws the new picture, then the
old clipped to the left of a divider, then the divider; a drag moves it, and it
starts in the middle. Changes draws the new picture, dims what is outside the
regions and outlines each region in the palette's modified colour, with the
count in the caption. The checkerboard is under everything, as in
`ImageFileView`, because a transparent edit is a real edit.

**The mode is a setting**, `pictureDiffMode`, read when the view is made and
written when the switch is used, so a person who works in *Changes* opens on
it. The same shape as `diffIsSideBySide` beside it.

**One-sided changes.** An added picture has a new side only, a deleted one an
old side only. Side by side shows the one and labels the other *no picture*;
slider and changes are unavailable and the switch says so rather than drawing
a comparison with nothing.

## Risks / Trade-offs

**A very large picture costs a bitmap of its own size** → Bounded: above 16
million pixels a side, the comparison is declined with a reason, side by side
and slider still draw the scaled images, and *Changes* says the picture is too
large to compare. The bound is the size of a 4k screenshot, which is the
ordinary large case.

**HEIC and WebP decode through ImageIO, which may not be present for every
format `FilePreview` names** → A side that will not decode is shown as *cannot
be read*, and the other still draws.

**The divider and the regions are drawn in points over a scaled picture** →
Positions are kept in picture pixels and converted at draw time, so a resize
of the pane keeps the divider where it was over the picture.

## Open Questions

- Whether *Changes* should also be offered as a blink — old and new alternated
  on a timer — which some reviewers prefer to boxes. Not in this change; the
  slider covers the same want more calmly.
