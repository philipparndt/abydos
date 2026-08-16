# 499. A Cadova model opens with the model beside it

[Cadova](https://github.com/tomasf/Cadova) is a Swift library for 3D models
aimed at printing — the same job OpenSCAD does, written as Swift instead of as
its own language. 0483 gives a `.scad` the model beside the text. A Cadova
model should open the same way.

**The difference that decides the design: a `.scad` is a file, a Cadova model
is a program.** OpenSCAD is handed a file and renders it. Cadova is an
executable target in a Swift package; you build it and run it, and it writes a
3MF beside the package.

## What was measured, before any of this was estimated

A spike, outside the repository, on this machine — Swift 6.4 against Cadova's
pinned 6.3.2, the hex key holder from the README compiled unmodified:

    swift package resolve      22s   once, 7 packages
    swift build (cold)         46s   719 units, Manifold's C++ included
    swift run                  3.1s  wrote hexholder.3mf beside the package
    edit one constant, rerun   3.8s, then ~2s

The 3MF is real: `3D/3dmodel.model`, 460 vertices, 916 triangles,
`Application: Cadova`.

**This is the finding that matters.** The cold build was estimated at "minutes"
and it is 46 seconds; the warm loop is about two, which is the same order as
re-rendering a `.scad`. So **previewing on save is viable**, and this does not
have to be a run configuration somebody invokes by hand. The estimate before
the spike had it the other way round.

## What already exists

- **3MF viewing.** `ModelPreview.previewableExtensions` is already
  `["stl", "3mf", "scad"]`, and 0482 put go3mf recipes in the viewer. The
  output end is done.
- **The split.** 0483 opens a `.scad` with the model beside it; this is the
  same arrangement with a different way of getting the mesh.
- **Running it** is 0498, which this needs and which is filed separately
  because a Swift package's executables are worth having in the run list
  whether or not anybody writes Cadova here.

## Worth deciding

- **What counts as "a Cadova model".** A `.swift` file is not enough — most are
  not models. The manifest depending on `Cadova` is the honest signal, and it
  is a package-level fact rather than a file-level one, so the question is
  really *which tab gets a viewer beside it*. The executable target's own
  sources are the obvious answer.
- **Where the 3MF is.** Cadova names it after the model — `Model("hexholder")`
  writes `hexholder.3mf` — not after the target or the file, and the name is
  inside the code. So the preview cannot know the path in advance: it either
  watches the package directory for what changed, or reads the line the run
  prints (`Wrote model to …`). Watching is more honest; parsing output is
  cheaper. Decide it.
- **A run that fails.** A compile error must reach the person as a compile
  error, not as a stale model and silence. `.scad` has the same problem and 0484
  is the item about it — read that before inventing something new.
- **How often.** Two seconds is fast but it is not free, and it is a whole
  package build. On save rather than on keystroke, debounced, and cancellable.

## Steps

- [x] Decide which tabs get a model beside them, and write the answer down
- [x] `SwiftPackage` reads targets, not only runnable names: what each one
      depends on and where its sources are
- [x] `CadovaModel` answers "which package, product and target does this file
      belong to, and does that target use Cadova"
- [x] `FilePreview` takes the facts a name cannot give as one value rather than
      as a growing list of booleans
- [x] Running the target produces a 3MF the viewer opens
- [x] Saving re-runs it, debounced, and the previous run is cancelled
- [ ] A build or run that fails says so where somebody will see it
- [x] A driver that reports what a Cadova pane is doing, so it can be watched
- [ ] Watched in the app: open a Cadova model, see geometry, change a constant,
      save, watch it change
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does

The four new steps are found work, not a bigger plan: the first two are
`SwiftPackage` not yet being able to map a *file* to a target (it holds
`(name, line)` per runnable product and nothing about sources or
dependencies), the third is `FilePreview.kind(for:looksLikeRecipe:)` needing a
second fact of the same shape at six call sites, and the fourth is that
`--run-config` from 0498 watches a *run*, and what has to be watched here is a
*pane*.

## Estimate

2026-08-16 13:55 — most of the afternoon
