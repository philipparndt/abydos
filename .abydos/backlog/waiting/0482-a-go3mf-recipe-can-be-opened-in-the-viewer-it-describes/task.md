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

## What was found, and why this is waiting

**Abydos's side is done. GoSTL's side cannot work, and this was checked on the
released `v0.20.2` that Abydos pins.** The premise above — *"GoSTL already has all of
it"* — is wrong, and it is wrong for a reason nobody could see from reading the Swift:

    $ go3mf build adapter-set.yaml -o /tmp/somewhere.3mf
      ✓ Build completed successfully!
      Output file: adapter-set.3mf          ← not /tmp/somewhere.3mf

**`go3mf` ignores `-o` when the recipe names an `output:`.** And `output:` is not
optional — a recipe without one is refused outright:

    $ go3mf build no-output.yaml -o /tmp/somewhere.3mf
      ✗ failed to load config: invalid configuration: output file must be specified

So *every valid recipe* makes `Go3mfToolRenderer.buildTo3MF`'s `-o <temp>` a no-op.
`App/Go3mf.swift:110` sets the recipe's own directory as the working directory, the
3MF lands **beside the recipe** under the name the recipe chose, `buildTo3MF` returns
successfully because `go3mf` exited 0 — and `AppState.swift:1185` then parses a
temporary file that was never written:

    Loading go3mf config: adapter-set.yaml
    ERROR: Failed to load file on startup: Error Domain=NSCocoaErrorDomain Code=260
    "The file “gostl_go3mf_1786538325.3mf” couldn’t be opened because there is no
    such file."

**And what the viewer then shows is worse than blank.** `loadFileOnStartup`'s `catch`
calls `setupInitialState(loadTestCube: true)`, so the pane fills with GoSTL's 50 mm
test cube — a confident, well-lit, correctly-shaded cube that is not your model and
does not say it is not your model. `images/0482-a-test-cube-where-the-model-should-be.png`
is the split working perfectly and showing the wrong thing.

Two consequences beyond "it does not work":

- **It writes into the project.** Opening the preview leaves `adapter-set.3mf` beside
  the recipe, overwriting whatever was there. The first draft of this item asked
  *"what if it overwrites one made by hand"* and the rewrite said that was "already
  answered upstream, and answered better". It is not answered at all — the temporary
  file the rewrite praised is the file that never gets written, and the one that does
  get written is the one in the project. The first draft was right to ask.
- **`AppState.swift:1359`'s rebuild-on-change has the same flaw**, and never runs
  anyway: `isGo3mf` is only set at the end of a load that throws first.

Measured on this machine: `go3mf` 0.16.5, `gostl` and `openscad` both installed at
`/opt/homebrew/bin`, GoSTL pinned at `v0.20.2` (`fcd36bf`). `go3mf build` on the real
recipe takes 0.28 s wall, so speed is not the problem here.

### What GoSTL says when it fails, including `go3mf` absent

`ContentView.handleLoadError` sorts errors into two places, and the difference matters:

- A `Go3mfError` — which is both `buildFailed` and the `go3mfNotFound` this item asked
  about — becomes an in-pane `ErrorOverlay`. So a machine with no `go3mf` does get
  told, in the pane, with the paths it looked in. That answers the "a viewer that
  opens blank is the worst outcome" worry for *that* case.
- Anything else becomes a modal `.alert`. The failure above is `NSCocoaErrorDomain
  260`, not a `Go3mfError`, so it takes this branch — an alert about a temporary
  filename nobody has ever heard of, over a test cube.

**Neither can be photographed by `--screenshot`**, and that is worth knowing before
the next person tries: the model pane is captured through GoSTL's Metal snapshot
provider (`snapshotHandle` in `makeModelView`), so every SwiftUI overlay in that pane
— the error overlay, the menu-panel button, the slicing panel — is structurally absent
from a capture. The cube in the attached image is the whole of what a capture can see.
The overlay's presence is read from the code, not from a picture.

### So it waits

**On a GoSTL that can load a recipe.** Either it stops passing `-o` and parses the
`output:` the recipe declares (relative to the working directory it already sets), or
it builds in a temporary *directory* so the recipe's own name lands somewhere harmless
— and the second is the one that also stops the preview from writing into the project.
Item **0481** is open in that fork now, which is where such a change belongs.

**Not Abydos's to fix**, and this was checked rather than assumed. Abydos hands the
viewer a URL and nothing else; every workaround on this side means Abydos running
`go3mf` itself and handing GoSTL the result, which is exactly the render pipeline this
item was rewritten to say is not ours — and it would be the thing writing into the
project. Predicting GoSTL's `gostl_go3mf_<unix-seconds>.3mf` filename so a rewritten
copy of the recipe lands on it was considered and is a race and a hack.

**Do not merge this branch before that lands.** The routing works, and a working door
to a wrong cube is worse than no door.

## Ruled out

- **Offering the viewer on every `.yaml`** and letting GoSTL's error speak, which the
  item asked to be weighed rather than dismissed. Rejected, and it was measured rather
  than argued. **In Abydos: 15 `.yaml`/`.yml` files, 0 recipes** — `project.yml` and a
  Helm chart kept in two copies. Wrong on every one. **In the directory this was asked
  for: 11 files at depth two, 11 recipes, across 7 unrelated projects** — and their
  names are `config.yaml`, `parts.yaml`, `frame.yaml`, `wheels.yaml`, `cards.yaml`.
  That second number is the more interesting one, because it says the rule is not
  fitted to the one file that prompted this: nothing in those names could have told
  them apart from a Helm values file, and the rule gets all of them. The precedent is
  in the same `switch` — `DiagramExport.holdsADiagram` exists precisely so `Export ▸`
  does not appear on every Markdown file — and this now sits beside it, reading the
  file the same way for the same reason. What the alternative would have bought is
  smaller than it looks, too: not "no detection code" but "no detection *rule*", since
  something still has to say which extensions are worth looking at.
- **The documentation URL in the recipe's header comment.** The strongest signal in the
  real file, and unusable: a recipe written from scratch or copied without the header
  is still a recipe, and a test that reads a comment tests which template a file came
  from. `Go3mfRecipeTests.ignoresComments` pins this — a file whose *only* recipe-like
  lines are commented out is not one.
- **`objects:` alone, or `output:` alone.** Either is common. Both at the top level, in
  this order of confidence, is the signature. It got stronger during the work rather
  than weaker: `output:` turns out to be *mandatory* in a recipe, so requiring it
  excludes no valid recipe at all — which was the one worry about naming it.
- **Letting `FilePreview.kind(for:)` read the file.** It would have been three lines
  and every existing caller would have kept working, and that is exactly the trap:
  `NewFileKinds.choose` calls it once per file in the project. The contents answer is
  a *parameter* instead, defaulting to `false`, so a caller has to ask for the read.
- **Re-reading the file to keep the answer fresh.** The verdict is decided once, when
  the tab opens, and kept on the `Tab`. The tab bar asks what modes a file has on
  every refresh and a refresh follows a keystroke; a question that reads the file
  cannot live there. The cost is that a `.yaml` which *becomes* a recipe while it is
  open stays text until it is reopened, which is the right way round.
- **Splitting a recipe by default, the way 0483 wants for `.scad`.** Kept as an option,
  and the reason is now stronger than "a recipe is source": a `.scad`'s preview is one
  OpenSCAD render, a recipe's is one render *per part* plus a `go3mf build` on top, and
  whether the file is a recipe at all was decided by reading the head of it. A default
  that starts that off the back of a guess is a default that makes opening YAML feel
  dangerous. Written into `FilePreview.defaultMode` beside the `.model` case so the two
  items do not read as an inconsistency.
- **Touching `ModelPreview.isViewableModel`.** It has no caller anywhere in the app —
  worth knowing, and 0483 owns the comment on it.

## Estimate

2026-08-12 14:52 — Abydos's side is done; waiting on GoSTL

## Steps

- [x] A content test for a go3mf recipe, bounded — say what it reads and how much —
      or a decided, written reason for not testing at all
- [x] Nothing that walks a tree reads a file to answer this
- [ ] A `.yaml` that passes reaches the embedded viewer, and GoSTL does the rest
- [x] The option is in the two places a model's already is — the tab's preview
      control and the navigator's *Preview in GoSTL* — and nowhere else
- [x] A recipe opens as its text and not as a model, and the difference from 0483's
      `.scad` is written down rather than inherited
- [x] What GoSTL's failure looks like from inside Abydos, including `go3mf` absent
- [x] Watched on `~/dev/3d/other/hubelino/adapter-set.yaml` — read-only, on a copy
- [x] Write down here what was ruled out on the way
- [ ] A GoSTL whose `go3mf` invocation survives a recipe that names its own `output:`
      — the reason this is waiting, and not Abydos's to write. See *So it waits*.
- [ ] `spec/<capability>.md` says what the project now does

The third step is unticked because it does not work, not because it was not tried: the
`.yaml` reaches the viewer and the viewer shows a test cube. The last step is unticked
on purpose — the spec says what the project *does*, and "a recipe can be opened in the
viewer" is not true yet. It gets written when the wait is over.
