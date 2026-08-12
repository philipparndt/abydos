# 482. A go3mf recipe can be opened in the viewer it describes

> in case it is a go3mf yaml file, there should be the option to open this in the
> embedded gostl:
> /Users/philipparndt/dev/3d/other/hubelino/adapter-set.yaml

That file says what it is in its own first lines:

    # Documentation: https://github.com/philipparndt/go3mf
    #   go3mf combine adapter-set.yaml
    output: adapter-set.3mf
    packing_distance: 10.0
    objects:
      - name: Adapter
        parts:
          - name: adapter
            file: ./adapter.scad

So it is not a model. **It is a recipe for one**, and `go3mf combine` is what turns
it into the `.3mf` the viewer can show. `go3mf` is on this machine at
`/opt/homebrew/bin/go3mf`.

## Two problems, and the first one is the interesting one

**Knowing that a `.yaml` is a go3mf recipe cannot be done by extension.** Every
mechanism in this area routes on the path: `ModelPreview.previewableExtensions` is
`["stl", "3mf", "scad"]`, `FilePreview.kind(for:)` is a `switch` on
`pathExtension`. A repository is full of YAML that is CI, compose files, Helm
charts and `.abydos/tools.json`'s cousins, and offering "open in the 3D viewer" on
all of them would be worse than not offering it at all.

So this needs a content test, and the constraint on it is where the cost lives:
`canPreview` is asked **per row** by the navigator's context menu
(`ProjectNavigatorViewController.swift:2515`), so it must not read files. Which
suggests the shape: the *menu item's* availability may cost a bounded read of the
head of one file — the file somebody actually right-clicked — while anything that
runs over a whole tree stays on extensions. Decide it deliberately and say what the
test is: `output:` plus `objects:` is a fair signature; the URL in a comment is not,
since a copy without the comment is still a recipe.

**And what "open in the embedded gostl" means for a recipe**, which is a render
step and not a viewer argument. `go3mf combine <file>` writes the `output:` the
recipe names — beside the recipe, which is somebody's directory, and that is a
decision: writing `adapter-set.3mf` where they expect it may be exactly right, or
may be a surprise the first time it overwrites one they made by hand. A scratch
copy is the other answer and costs the thing they may have wanted.

**This is the shape the OpenSCAD path already has**, and it is worth reading before
inventing a second one: a source file, an external tool, a mesh, then the viewer.
Whatever caching, error reporting and staleness rules that path settled, this should
answer the same way or say why it differs — a recipe whose parts are `.scad` files
means `go3mf` will itself invoke OpenSCAD, so a single press can be two tools deep
and the failure of either has to arrive somewhere legible.

## Worth deciding

- **Whether it is an option or a default.** The report says *option*, and that fits:
  a recipe is source, its parts are source, and combining it is work. 0483 asks for
  `.scad` to open with the model beside it, so if these two land together the
  question of whether a recipe should too has to be answered rather than inherited.
- **What happens when `go3mf` is not installed.** `ModelPreview.executable()` exists
  for exactly this and looks in the Homebrew locations directly, because a GUI app
  does not inherit a login shell's `PATH`. Follow it rather than trusting `PATH`.
- **Whether the produced `.3mf` is watched.** Editing the recipe or one of its
  `.scad` parts should not leave a stale model looking current. What the OpenSCAD
  path does about this is the precedent.

## Steps

- [ ] A content test for a go3mf recipe, and a bounded one — say what it reads and
      how much
- [ ] Nothing that walks a tree reads a file to answer this
- [ ] `go3mf combine` from the app, with a decided answer about where the output
      goes and what happens to an existing file there
- [ ] The failure of either tool arrives somewhere somebody will see it, including
      when `go3mf` runs OpenSCAD underneath
- [ ] Absent `go3mf` is said, not silently missing, and found the way
      `ModelPreview.executable()` finds gostl
- [ ] Watched on `~/dev/3d/other/hubelino/adapter-set.yaml`, which is where it was
      asked for — read-only, on a copy
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
