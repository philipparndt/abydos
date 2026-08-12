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

## What it cost, measured

All of this on an eight-core M1 Max with **two other agents building in the same
repository**, so every number below carries its one-minute load average. 0472 exists
because timings from this machine were being read as regressions; these are not a
baseline for anything.

**The renderer.** OpenSCAD 2026.06.12, and note that GoSTL looks at
`/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD` *before* `/opt/homebrew/bin`,
which here are the same binary — the Homebrew path is a symlink into the bundle. So
0434's developer snapshot is what runs, and it is the fast one: it renders through
Manifold rather than CGAL.

**A cold render, from the app's own stall log** (`~/Library/Logs/Abydos/stalls.log`),
which is the honest instrument because the render blocks the main thread. Two runs at
a comparable load of 34–37, the only difference being which file was opened:

    main.swift   (no render)   579 ms  cpu 98%
    adapter.scad (split)       110 ms  cpu 93%
                               339 ms  cpu 12%   ← the render

`cpu 12%` is the reading that names it: the main thread was not executing, it was
inside `waitUntilExit` waiting for OpenSCAD. **So a cold `.scad` costs about 340 ms of
window that does not draw, at a load average of 34.** GoSTL's own breakdown for the
same open: CSG conversion 87 ms, colour extraction 129 ms, then a full STL render
whose duration it does not print, then parse 2.7 ms and a spatial index in 1.8 ms.

**Warm**, meaning the same file re-rendered in the same process after an external edit
(GoSTL's watcher, driven by `--external-edit`), at load 39: CSG 61 ms, colours 69 ms —
so a little under two thirds of cold, and the difference is page cache rather than
anything either program does.

**Standalone, on a quiet machine at load 5**, the three OpenSCAD invocations GoSTL
makes measured 60–110 ms each on this corpus, which puts a quiet-machine cold render
nearer 200 ms.

**The comparison that decided the item.** 200–340 ms is *cheaper* than the split two
cases above it in the same function: a `.puml` starts a JVM, and
`PlantUMLPreviewView` debounces by 400 ms before it even begins. So the third
possibility the item raised — that a model is genuinely different because a mesh
render costs seconds where a diagram costs milliseconds — is false on this corpus
with this OpenSCAD, and it is false in the *other* direction from the one expected.
It would come back on a `.scad` heavy enough to take seconds, and the lazy build
below is what keeps that from being paid twenty times over.

### It happens on the main actor, and that is upstream

Worth writing down because it bounds everything above. GoSTL loads a file like this:

    appState.isLoading = true
    Task { @MainActor in
        do { try appState.loadFile(url, device: device) }

and `loadFile` runs OpenSCAD synchronously. So the render's duration is time the whole
window is frozen, not time a spinner spins — the `LoadingOverlay` is set before the
hop and drawn after it, which is why the stall reads `cpu 12%` rather than showing a
progress view. Abydos cannot move it: the package is pinned at 0.20.2 and 0481 is in
the fork. What Abydos *can* do is make sure it happens once, for the file somebody
stopped at, which is what the lazy build is.

## What twenty at once does, and what a walk does

Driven through the app, counting GoSTL's own `Rendering OpenSCAD file:` lines and its
`ContentView.onAppear`, which is the moment a viewer exists at all:

| what was done | viewers built | renders |
| --- | --- | --- |
| twenty `.scad` opened together (`--file` ×20) | 1 | 1 |
| three opened together | 1 | 1 |
| tree walked down 20 rows without pausing | 0 | 0 |
| walked across two rows, then paused 1 s on the third | 1 | 1 |

The last two lines are the whole guard, and they are the same run: crossing
`adapter-feder.scad` in a tight loop rendered nothing, and stopping on `adapter.scad`
rendered exactly it. The twenty-at-once line is `part9.scad`, the tab left in front;
the other nineteen tabs exist, have their splits built, and have never been in a
window, so they cost nothing until somebody clicks them.

**How that works, and why it is keyed where it is.** `ModelContainerView` builds the
GoSTL hosting view from `viewDidMoveToWindow` rather than from its initialiser, after
`startAfter` seconds — 0.4 for a provisional tab, 0 (next runloop turn) for one
somebody committed to. Leaving the window cancels the pending build. That one hook
answers all four rows above: a provisional tab recycled by the next row is removed
from `contentArea` before its 0.4 s is up, and a tab that was never in front was never
added to it.

0.4 s is not a new number: it is the debounce `PlantUMLPreviewView` already uses to
keep a walk from starting a JVM per row, and using the same one means there is one
answer in this codebase to "how long before a preview is worth paying for".

**0470 was read first, as the item asked, and it does not cover this.** Its
measurement — 210 keypresses costing 5 `didOpen`s — holds because the traffic is one
notification per *file crossed*, and five presses inside one file add nothing. Every
row of a directory of `.scad` files is a different file, so that argument gives no
protection here at all. It names the exposure rather than removing it.

## Where no OpenSCAD, and a file that does not compile, actually land

Asked, and the answer is worse than the code comments promise, so it is filed as
**0484** rather than described as a feature.

A `.scad` with a syntax error in it shows **a cube**, lit and on the build plate, with
no message anywhere — watched at 7 s and again at 16 s, so it is not an overlay
arriving late. `images/` in 0484 has the screenshot. A machine with no OpenSCAD takes
the same path, because `openSCADNotFound` propagates out of `loadFile` exactly as a
parse error does, so it too gets a cube instead of the install instructions GoSTL has
written and reached.

It is a race inside upstream between two of its own handlers: the failure path sets
`overlayError` and then calls `setupInitialState(loadTestCube: true)`, and loading
clears `appState.loadError`, whose `onChange` dismisses the overlay one line after it
was set. 0484 has the code.

This has been true for as long as the embedded viewer has, and it mattered less while
the preview was something somebody asked for. It matters more now, which is the one
real cost this item adds, and it is why the spec delta says nothing about failure
rather than writing a requirement nobody chose.

## Ruled out on the way

- **Giving the model the larger half.** Tried first, at 0.4, on the reasoning in the
  item: a mesh is turned around and wants area, a line of OpenSCAD is narrow. Watched
  it, and it is backwards. At a 1280 pt window the source half was 389 pt and
  `adapter.scad` — the file that asked for this feature — was clipped mid-comment with
  a horizontal scroller, while the viewport around the part had margins to spare. **A
  3D view zooms to fit, so it degrades gracefully with less width; text stops at a
  hard edge.** And the longest line of the median `.scad` in the owner's own 493 of
  them is 93 columns (p75 150), which no fraction of a 970 pt editor fits — so the
  divider is not the lever, and half is the answer for the same reason it is
  everywhere else. `FilePreview.defaultDividerFraction` existed for an hour and was
  deleted; the finding is a comment where the fraction is set.
- **Committing-only, i.e. a provisional tab opening as plain text and gaining the
  model when somebody commits to it.** Simple, no timers, and it was nearly the
  answer. Rejected because a single click is how a file is usually opened here, so it
  would have handed back a feature that does not do what was asked on the gesture
  people use. The debounce gives both: a click shows the model 0.4 s later, a walk
  shows nothing.
- **Refusing to split when OpenSCAD is not installed**, so nobody gets a cube. It
  would need `FilePreview.defaultMode` — a pure function over a URL, in AbydosKit — to
  start asking the filesystem what is installed, and it would not help the case that
  actually happens to somebody who *has* OpenSCAD, which is a file with an error in
  it. The pane saying so is the better answer, and 0484 is that.
- **Fixing 0484 here.** It is upstream, in a package pinned at 0.20.2, and 0481 is
  already working in that fork. Two agents editing GoSTL is one of them losing.
- **A counter in Abydos for "viewers built", in 0470's style.** Not needed: GoSTL
  prints `ContentView.onAppear` and `Rendering OpenSCAD file:` on its own, which is
  the same reading from the program that does the work rather than from a number
  Abydos keeps about it.

## And 0482, which lands beside this

Both were read. They stay different, and the difference is not arbitrary: **a `.scad`
is a model, and a go3mf `.yaml` is a recipe for combining several.** The extension of
a `.scad` says what it is, so it can open as what it is; a `.yaml` says nothing — a
repository is full of CI, compose files and Helm charts — so it has to be asked for,
and 0482's option is the right shape for it. Written here so that the two answers are
not read as one of them being an oversight.

## Estimate

2026-08-12 14:56 — about twenty minutes left, on the suite

## Steps

- [x] Which mechanism grows: `FilePreview` already did, and `isViewableModel` is
      dead — say so, and delete it rather than leave two comments arguing
- [x] `.scad` opens split right, with the divider where a mesh wants it
- [x] Measure a cold and a warm render, saying what the load was
- [x] A provisional open does not start a render per row, and neither does a
      restored session of twenty
- [x] Say what happens with no OpenSCAD and with a slow render
- [x] Watch it on a real `.scad`, cold and warm
- [x] File what a failed render shows, since this default is what makes it matter
      (0484)
- [x] Write down here what was ruled out on the way
- [x] `spec/previews.md` says what the project now does
