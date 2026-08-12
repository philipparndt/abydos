# 483. A scad file opens with the model beside it

> and scad files should be opened with split right by default

The precedent is already in the file that would have to change, and it argues for
this in the same words. `FilePreview.defaultMode(for:)`:

    case .plantuml, .mermaid:
        // Both halves at once: the text is what is edited and the diagram
        // is what it is for, and checking one against the other is the
        // whole of the work.
        return .splitRight

That is exactly a `.scad` — source somebody types, whose whole purpose is the shape
it makes.

## Why it is not a one-line change

**A `.scad` is not in that mechanism at all.** `FilePreview.kind(for:)` is a switch
over `image`, `plantuml`, `mermaid`, `drawio` and `pdf`, and a `.scad` reaches none
of them. The 3D viewer is a *separate* path — `ModelPreview.previewableExtensions`
is `["stl", "3mf", "scad"]`, and `ModelPreview.isViewableModel` deliberately leaves
`scad` out with its own comment:

    /// OpenSCAD is left out: a .scad file is source, and editing it is the
    /// point — its preview is a separate tab, opened deliberately.

**So this item overturns a written decision, and should say so rather than quietly
contradicting it.** That comment is right that a `.scad` is source; what it got
wrong is the conclusion that its preview must therefore be asked for, when
PlantUML's comment two files away reaches the opposite conclusion from the same
premise. One of the two has to change, and the third possibility — that they are
genuinely different because a mesh render costs seconds where a diagram costs
milliseconds — is the thing to weigh rather than skip.

Which is the real question here: **what a default split costs.** Opening a `.scad`
would start OpenSCAD, and 0434 established this project depends on a *developer*
snapshot rather than the five-year-old stable release. So the default has to answer:
what happens when OpenSCAD is not installed, when the render takes ten seconds, and
when somebody opens twenty `.scad` files from a search result. A default that turns
every click into a render is a default that makes the tree feel broken.

## Worth deciding

- **Which mechanism grows.** Either `FilePreview` learns a model kind and the two
  paths meet, or the model path gets its own default mode. They currently answer
  different questions — one is "what does this file open as", the other is "can the
  viewer show it" — and this item makes them overlap for the first time.
- **Whether a provisional open splits too.** A single click in the tree opens a
  provisional tab; splitting one so that arrowing down a directory of `.scad` files
  renders each in turn would be the same mistake as 0470's tab-per-usage, which was
  measured and avoided there.
- **What the divider is set to.** `PreviewSplitView` keeps a fraction until it has a
  size, which is the right machinery; the number is a judgement, and for a mesh the
  useful half may not be the same half a diagram wants.
- **Whether the preview is the embedded viewer or the render tab.** These may already
  be the same thing; if they are not, say which one "split right" means.

Related: **0482** asks for a go3mf recipe to be openable in the viewer, and settles
that as an *option* rather than a default. If both land, the two answers have to be
consistent or the reason for the difference has to be written down.

## What was found before starting

**The premise above is stale, and in the item's favour.** `FilePreview.kind(for:)`
*does* already answer for a `.scad`:

    case "scad", "stl", "3mf":
        return .model

It has done since a110bcc, "Choose source, preview or split from the tab bar", the
commit that invented `FilePreview` and moved this decision into it. So there is no
second mechanism to join up — and `ModelPreview.isViewableModel` **has had no caller
since that same commit**. `grep -rn isViewableModel Sources Tests` finds exactly its
own definition, and nothing else.

The two files were therefore never disagreeing about anything the program does: one
comment describes behaviour, the other describes a function nothing asks. That
settles "which mechanism grows" by deletion rather than by design, which is a better
answer than either the item offered.

## Estimate

2026-08-12 14:25 — about ninety minutes left

## Steps

- [x] Which mechanism grows: `FilePreview` already did, and `isViewableModel` is
      dead — say so, and delete it rather than leave two comments arguing
- [x] `.scad` opens split right, with the divider where a mesh wants it
- [ ] Measure a cold and a warm render, saying what the load was
- [ ] A provisional open does not start a render per row, and neither does a
      restored session of twenty
- [ ] Say what happens with no OpenSCAD and with a slow render
- [ ] Watch it on a real `.scad`, cold and warm
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does
