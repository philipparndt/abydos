# 507. A Cadova model opens split and the right half stays empty

> I now also tried the cadova integration but something is missing, I do not see
> the 3D Model in the split view … but exactly this would make the integration
> nice

0499 shipped and the split opens. Nothing appears in it. Screenshot with the
report: `main.swift` of the `hex-key-holder` target open, Split Right active,
the right half empty — no model, and no visible notice either.

## What has been measured, so nobody repeats it

All of this against the real fixture,
`abydos-examples/cadova-models/Sources/HexKeyHolder/main.swift`, and a pristine
copy of it with no session history. **Everything up to the pane is correct.**

- **Detection works.** `CadovaModel.find(for:stoppingAt:)` returns
  `product: "hex-key-holder"`, `packageDirectory: …/cadova-models/`,
  `sources: […/Sources/HexKeyHolder/]`. Driven directly from a test in the
  0499 worktree.
- **`SwiftPackage` reads the manifest right**, including the product rename:
  targets `HexKeyHolder exec=true deps=["Cadova"]` and `coaster` likewise,
  `target(containing:)` → `HexKeyHolder`, `runnableName(for:)` →
  `hex-key-holder`.
- **The app decides correctly.** Probes printed from `makeTab`:
  `facts=PreviewFacts(looksLikeRecipe: false, isCadovaModel: true)`,
  `hasPreview=true`, `opening=splitRight`. So `CadovaPreviewView` **is** built.
- **The run itself works and prints what the parser expects.** `swift run
  hex-key-holder` in that package: `Wrote model to …/Models/hex-key-holder.3mf`,
  and the file is there. `Project(packageRelative: "Models")` writes into a
  subdirectory but the message is the same shape a bare `Model` produces.
- **It fails in 0499's own build too**, not only in the installed one — so it is
  not a stale app. The installed build (17:35, after the 14:50 merge) contains
  the code.
- **The toolchain is not it**: the login interactive shell resolves
  `/usr/bin/swift`, Swift 6.4, against Cadova's `swift-tools-version: 6.3`.

## Where it therefore is

Inside `CadovaPreviewView`, or in what the tab does with it. Two candidates,
neither confirmed:

- **`whenShown` never fires.** The pane inherits 0499's lazy guard — nothing
  starts until it has been on screen for `startAfter`, and nothing starts at all
  if it leaves first. A pane that is built but never considered "shown" would
  sit at its initial `notice`, which is `"Waiting to build hex-key-holder…"`.
  **The reported screenshot shows no text at all**, which does not match that
  notice — so either the notice is not being drawn either, or the pane in the
  window is not this view.
- **0499's own driver cannot see it.** `--cadova-watch` prints `no cadova pane
  in the tab in front` for the whole run, on the fixture, in 0499's own build —
  while the probes above prove a `CadovaPreviewView` was constructed for that
  file. So `cadovaPreview` / `cadovaPane(in:)` and the real view tree disagree.
  That is either the bug or a second one sitting on top of it, and it is the
  reason 0499 was watched green: **it was watched against the scratchpad
  `cadova-spike`, a one-target package, not against this fixture.**

## Worth deciding

- **Whether the pane says anything while it waits.** Whatever the cause, a
  minute of empty grey is the thing the reporter actually hit. A cold build here
  is 30–60 s. 0484 is the item about a `.scad` that will not render and is the
  precedent for what an empty preview should say.

## Steps

- [ ] Reproduce with the driver against the fixture, and make the driver agree
      with reality — a pane that exists must not be reported missing
- [ ] Find why nothing appears: whether `whenShown` fires, and what the pane is
      showing when it does not
- [ ] Fix it, and say in here which of the two candidates it was
- [ ] The pane says what it is doing while it does it, including the first cold
      build
- [ ] Watched against **this** fixture, not the spike, with a screenshot of the
      model in the split
- [ ] A regression test that would have caught this — 0499's watching passed
      because it used a package with one target and no product rename
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does, if the behaviour it
      describes turns out to be wrong rather than just absent
