# 482. A go3mf recipe can be opened in the viewer it describes

> in case it is a go3mf yaml file, there should be the option to open this in the
> embedded gostl:
> /Users/philipparndt/dev/3d/other/hubelino/adapter-set.yaml

and then, correcting the first draft of this item:

> gostl can show such files as 3d objects and also export and open them

**Which is true, and it is nearly the whole item.** The first draft of this entry
designed a render pipeline for Abydos to run — `go3mf combine`, a decision about
where the `.3mf` lands, staleness, error reporting. None of that is ours to build,
because GoSTL already has all of it:

- `App/AppState.swift:1187` — `else if fileExtension == "yaml" || fileExtension ==
  "yml"`, which builds and loads it like any other model.
- `App/Go3mf.swift:110` — `buildTo3MF(yamlFile:outputFile:)`, running
  `go3mf build <yaml> -o <out>` with the recipe's own directory as the working
  directory, and the login shell's `PATH` inherited so `go3mf` can find OpenSCAD
  underneath.
- The output goes to a **temporary** file, `gostl_go3mf_<timestamp>.3mf`, not beside
  the recipe. So the "where does the output go, and what if it overwrites one made
  by hand" question the first draft raised was already answered upstream, and
  answered better.
- `AppState.swift:1372` rebuilds to a fresh temp on change, so staleness is handled.
- `AppState.swift:1733` already lists the contract: *"expected .stl, .3mf, .scad, or
  .yaml"*.

Also corrected: the command is `go3mf build`, not the `combine` the recipe's own
comment shows. Both may exist; `build` is what GoSTL calls.

## So what is actually missing

**Only Abydos's side of the door.** `ModelPreview.previewableExtensions` is
`["stl", "3mf", "scad"]` and `ModelPreview.isViewableModel` is `["stl", "3mf"]`, so a
`.yaml` never reaches the viewer no matter what GoSTL could do with it. The feature is
a routing change, and the one real problem in it is the one the first draft got right:

**A `.yaml` cannot be recognised by its extension.** Every mechanism here routes on
the path, and a repository is full of YAML that is CI, compose files, Helm charts and
lock files. Offering "open in the 3D viewer" on all of them would be worse than not
offering it.

And the cost matters, because `canPreview` is asked **per row** by the navigator's
context menu (`ProjectNavigatorViewController.swift:2515`), so it must not read
files. The shape that suggests: the *menu item's* availability may cost a bounded
read of the head of the one file somebody right-clicked, while anything that runs
over a whole tree stays on extensions. Say what the test is — `output:` together
with `objects:` is a fair signature; the documentation URL in a comment is not, since
a copy without the comment is still a recipe.

An honest alternative worth weighing rather than dismissing: **offer it on every
`.yaml`** and let GoSTL's own error say so when it is not a recipe. That costs a
useless menu item on a thousand files and buys no detection code, and the reason it
is probably still wrong is that the useless item is on *every* one of them.

## Worth deciding

- **Option or default.** The report says *option*, and that fits: a recipe is source
  and its parts are source. 0483 asks for `.scad` to open with the model beside it as
  a *default*, so if both land the difference has to be explained rather than
  inherited.
- **Where the option lives.** The navigator's context menu is where `canPreview` is
  already consulted; whether the editor showing the YAML as text should also offer it
  is the same question 0483 asks about `.scad`.
- **What GoSTL says when `go3mf` is absent**, and whether that arrives anywhere in
  Abydos. `findGo3mfExecutable` throws; where that throw surfaces in an embedded
  viewer is worth one look.

## Estimate

2026-08-12 14:23 — about two hours left

## Steps

- [ ] A content test for a go3mf recipe, bounded — say what it reads and how much —
      or a decided, written reason for not testing at all
- [ ] Nothing that walks a tree reads a file to answer this
- [ ] A `.yaml` that passes reaches the embedded viewer, and GoSTL does the rest
- [ ] The option is in the two places a model's already is — the tab's preview
      control and the navigator's *Preview in GoSTL* — and nowhere else
- [ ] A recipe opens as its text and not as a model, and the difference from 0483's
      `.scad` is written down rather than inherited
- [ ] What GoSTL's failure looks like from inside Abydos, including `go3mf` absent
- [ ] Watched on `~/dev/3d/other/hubelino/adapter-set.yaml` — read-only, on a copy
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
