# 500. An example Cadova model, for the fixtures that need one

0424 made the examples repository the fixture for anything that cannot be
tested by reasoning: `ExampleProjects.root` finds `../abydos-examples` beside
this checkout — or three levels further up, when the caller is in a worktree —
and every test using it skips cleanly when it is not there.

*Corrected while doing the work:* this item was filed saying eighteen
`*LiveTests` use it. Eighteen files are named `*LiveTests`, but
`ExampleProjects.root` had exactly one caller —
`DevContainerLifecycleLiveTests.swift:197`. The other suites that want the
examples repository walk up from `#filePath` themselves. The claim is true of
the fixture and was not true of the symbol.

0498 and 0499 both want one of these. Discovering a Swift package's executables
and previewing what one of them writes are exactly the claims that cannot be
argued, only run.

## What it has to be

A Swift package depending on Cadova, with at least one executable target that
writes a 3MF. The hex key holder from Cadova's own README compiles unmodified
and is a reasonable size — measured in the 0499 spike: 22s to resolve, 46s to
build cold, ~2s warm, and a 3MF with 460 vertices and 916 triangles.

Two targets rather than one would be worth it, so 0498's discovery has
something to disagree about.

## Worth deciding

- **Whether it is checked in built or built by the test.** A cold build is 46
  seconds and pulls seven packages from the network. That is fine for a live
  test that skips when the repository is absent, and it is *not* fine anywhere
  it could land in the ordinary suite. Keep it on the skipping side of that
  line, the way the container tests are.
- **Version pinning.** Cadova is pre-release below 1.0 and says the API moves
  between minor versions; it recommends `upToNextMinor`. An example that stops
  compiling in six months is worse than no example, so the manifest should pin
  and `Package.resolved` should be committed.
- **Which repository the item is done in.** The example lives in
  `abydos-examples`, which is a different checkout with its own history. This
  item's commits are mostly not in this repository, and it should say so
  plainly when it is finished.

## What was decided, and why

**Neither checked in built nor built by the ordinary suite.** The choice as
filed was between two options, and the interesting thing turned out to be that
"a live test that skips when the repository is absent" is not on its own the
line the item wanted. The examples repository is beside the checkout on any
machine somebody works on, so a test gated only on its presence *is* the
ordinary suite. So the line was drawn one step further in, exactly where
`BuiltToolImageLiveTests` draws it for an image it would have to build:

- Reading the manifest costs nothing and runs whenever the fixture is there.
- Running the models runs when the package is **already built**, and otherwise
  only for `ABYDOS_BUILD_EXAMPLES=1`. Nothing in `make test` ever starts the
  65-second build or reaches the network.

Nothing built is committed. `.build` and `Models/*.3mf` are ignored in the
examples repository, for the reason `*.stl` already was: a model file in git is
the output of the source beside it, and nothing notices when the two stop
agreeing. A checked-in 3MF would also have made the fixture answer the question
0499 wants to ask — whether a *run* produces one — before the run happened.

**Pinned, as the item said, and the pins committed.**
`.upToNextMinor(from: "0.9.0")`, which is what Cadova's own README asks for
below 1.0, with `Package.resolved` naming all seven packages by revision. The
live test asserts both, so the pin cannot quietly be dropped.

## Which commits are in which repository

The work is in two repositories and mostly not in this one.

**`abydos-examples`**, branch `backlog/0500-an-example-cadova-model` — pushed,
not merged:

- `df71acd` — `cadova-models/`: the package, both models, `Package.resolved`,
  its README, the row in the repository README, a `make models` goal, and the
  `.gitignore` lines for `.build` and `Models/`.

**`abydos`** (this repository), branch
`backlog/0500-an-example-cadova-model-for-the-fixtures-that-need-one` — pushed,
not merged. Three commits, all of them either this item or
`Tests/AbydosKitTests/CadovaExampleLiveTests.swift`. No source file of the app
was touched, because nothing about the app changed.

## Ruled out, and what surprised us

- **A directory called `cadova` cannot hold a package that depends on Cadova.**
  This cost the first half hour and produces no error worth the name. SwiftPM
  takes a package's identity from its directory name and a dependency's from
  its URL, so in `examples/cadova` the package declares a dependency on itself:
  `swift package resolve` exits **0 in 0.3 s**, fetches nothing, writes no
  `Package.resolved`, and leaves a `.build` with an empty dependency list. The
  first complaint comes from the build — `product 'Cadova' required by package
  'cadova' target 'coaster' not found` — which reads like a mistake in the
  manifest. Hence `cadova-models`, said in the manifest, in the README and
  here, since the obvious tidy-up is to rename it back.
- **`Model("name")` was ruled out in favour of `Project(packageRelative:)`.**
  A bare `Model` writes to the working directory, so where the 3MF lands
  depends on who started the program — a terminal, the run list and Xcode all
  choose differently, and a preview looking for the file would be right only
  sometimes. `Project(packageRelative: "Models")` writes beside the package
  whatever the working directory is.
- **`swift package dump-package` was not needed and was not used**, which is
  the point 0498 already made; the live test reads the same manifest with
  `SwiftPackage.find` and never runs it.
- **The item's arithmetic held.** The spike's figures reproduced: resolve 23 s
  here and 19 s in a clean clone, cold build 55–65 s at `-j 4`, a run about
  3 s, and the hex key holder is 460 vertices and 916 triangles to the vertex.
  The coaster is 1,280 and 2,556.
- **A third executable was not added.** Two is what the decisions need — a
  product whose name differs from its target, and a bare target — and a third
  would be a third thing to keep compiling against a pre-release API.
- **Not fixed here: three copies of the walk to the examples repository.**
  `ExampleProjects.swift`, `ExampleMermaidTests.swift` and
  `ExampleDevContainerTests.swift` each find `../abydos-examples` themselves and
  do not agree — two of them canonicalise, and each gates on a different
  subdirectory. The new test uses `ExampleProjects.root` and adds no fourth
  copy. Worth an item of its own; not one to do inside this one.
- **Their comment about worktree depth is wrong, and it did not matter.** All
  three say a worktree lives at `.claude/worktrees/<name>` and try the parent
  and four levels up. This worktree is a direct sibling of the checkout, so the
  *first* candidate found the repository — by luck rather than by the stated
  rule. Anybody debugging a skip should know that before believing the comment.

## Steps

- [x] A Cadova package in `abydos-examples`, pinned, with `Package.resolved`
      committed, and more than one executable target
- [x] It builds and writes a 3MF from a clean checkout
- [x] A live test that uses it and skips cleanly when the examples repository
      is not beside this one
- [x] Settle in writing which side of the ordinary suite the *building* is on,
      since the fixture being present is the ordinary case on a working machine
- [x] Say in the item which commits are in which repository
- [x] Write down here what was ruled out on the way
- [x] The spec, if this changes what the project does — it may not, and saying
      so is the answer rather than skipping the step

## No spec delta, and why

**Nothing about what the app does changed, so there is nothing for `spec/` to
say.** Not a step skipped — the answer.

What this item added is a fixture in another repository and a test that drives
it. No file under `Sources/` was touched. The behaviour the fixture exercises is
already written down, and written down as of 0498: `spec/run-configurations.md`
holds *A Swift package offers its executables and its tests*, whose scenario
"a package with two executables and one of them renamed" describes precisely
what `cadova-models` now is on disk — a product `alpha-tool` for a target
`AlphaTarget` and a second bare executable target, spelled here as
`hex-key-holder` for `HexKeyHolder` and `coaster`. The requirement beside it,
*A manifest is read and not run*, is the one the cheap half of the test
defends.

So the fixture makes an existing requirement checkable rather than making a new
claim. A delta here would either repeat those two requirements or add a
requirement about the test suite, and the spec is what the project does, not
how it is tested.

## Estimate

2026-08-16 14:12 — done, bar the pushes
