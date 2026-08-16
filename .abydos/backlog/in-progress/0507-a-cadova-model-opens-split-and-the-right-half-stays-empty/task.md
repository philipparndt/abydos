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

## What it was: the pane was talking to nobody

**Neither of the two candidates. A third, and it was in the pane all along.**

`CadovaPreviewView` has exactly three things it can be showing, and the screenshot
rules out two of them:

- **A model.** GoSTL draws it, and 0499 photographed one rendering correctly. The
  reporter saw no model.
- **A notice** — `Waiting to build…`, `Building hex-key-holder…`, the last line of
  the build. Drawn in `draw(_:)`, and drawn only `guard viewer == nil, let
  notice`. The reporter saw no text.
- **A failure**, which is `show(failure:)`: it sets `notice = nil`, takes the
  viewer away, and unhides `failureScroll`. In that state `draw(_:)` fills the
  background and returns at its own guard, so the pane paints *nothing at all* —
  and what should have covered it is the text view.

So the pane was in the failure state. And the failure state showed nothing,
because `failureText` is an `NSTextView()` that was never given a size:

    failureScroll.documentView = failureText

An `NSTextView()` is built with a zero frame and a zero text container, and a
scroll view does not size its document view — a clip view positions one. Without
`isVerticallyResizable`, `autoresizingMask` and `widthTracksTextView`, the text
view stays 0 × 0 and lays out **no glyphs**.
`EditorViewController.makePreviewView` — the Markdown pane, the same shape, in the
same window — sets all four. This one set none.

That is the whole of the reported fault: *every* Cadova failure — a compile error,
a toolchain that will not read the manifest, `swift` not on the PATH, too many
tool processes — has been an empty grey half since 0499 shipped. The pane was
saying the right thing to nobody.

**Why 0499's watching missed it**, and this is the part worth keeping: the driver
reads `failureText.string`. A `String` is in a text view whether or not a single
glyph of it is laid out, so `--cadova-watch` printed
`state=failed said=…/main.swift:6:24: error: use of local variable…` — correct,
convincing, and about a pane that was blank. 0499 watched that line go past and
took it as the failure path working. `reportForTesting` now carries `drawn=`, the
size of what the pane actually paints, and `drawn=0x640` beside `state=failed` is
what would have caught this — see the measurements below, which is where that
number came from and where the first attempt at it is corrected.

**And a fault in the driver's own launch parsing.** `--cadova-watch` consumed the
argument after it whether or not it was a number, so `--cadova-watch --file
…/main.swift` ate the `--file`: the app opened no file, and the driver then
reported — truthfully — that there was no Cadova pane in the tab in front, for the
whole run. There is nothing wrong with `cadovaPreview` or `cadovaPane(in:)`:
`makeTab` puts the pane in the split, the split is `tab.contentView`, and the
search is over that. `--cadova-watch` now peeks, the way `--backlog`, `--tab-add`
and `--devcontainer` already do in the same file for the same reason, and a
negative answer names what *is* in front instead of only what is not.

## Measured afterwards in the app, and two paragraphs above needed correcting

The section above was written by an agent whose sandbox refused every build, test
and app launch, and it says so. It has now been built and watched. **The fix is
right and the diagnosis of the empty pane is exactly right** — the symptom is
reproduced, photographed, fixed and photographed again. Two claims around it are
not, and both are the kind only a run settles.

**1. `drawn=` as first written would not have caught this.** It asked the layout
manager, and a layout manager lays glyphs out happily in a container nobody sized
and then reports how big they came out. Measured on the two builds, same fixture,
same broken source:

    usedRect, pane unfixed   1689 × 39     ← the "78 points" of text nobody saw
    usedRect, pane fixed        …  × 156

A number that goes 39 → 156 separates nothing, and `drawn=0` was never going to
appear. The probe that settled it, printed from the unfixed pane in the app:

    frame 0 × 640,  container -28 × 10000000,  used 1689 × 39,  scroll 548 × 640

**The text view was zero points wide and full height.** So every height anybody
could have measured — from the frame or from the layout manager — looked healthy
for a pane showing nothing at all; the width is the one that was zero. `drawn=` is
now a *size*, taken from the text view's own frame clipped to the scroll view:

    drawn=0x640     unfixed, state=failed, with the compiler's line in `said=`
    drawn=533x640   fixed, same run

which is the instrument this item asked for.

**2. The eaten `--file` is not why the report at the top of this item says what it
says.** Run against the real fixture with a number after the flag, so nothing was
eaten:

    Abydos --open …/cadova-models --file …/HexKeyHolder/main.swift --cadova-watch 40
    CADOVA: 0s no cadova pane in the tab in front        (…and so on, for 40 s)

Still. The honest driver named it in one line:

    CADOVA: 0s no cadova pane — tab=~/Library/Caches/abydos/index/cadova-models-…
      /checkouts/Cadova/Sources/Cadova/…/Extrusion.swift mode=source cadova=none
      open=[Extrusion.swift] content=[NSScrollView … CodeView …]

The Cadova tab was not behind another one — **it was gone, and so was the
project.** A stack from `open(fileURL:)` says why, and it is nothing to do with
previews:

    BottomPanel.reportWorkingDirectory
      → MainWindowController.terminalDirectoryChanged(to:)
      → switchProject(to:followingTerminal: true)
      → EditorAreaController.restore(ProjectSession)
      → open(fileURL: …/Extrusion.swift)

`cadova-models` is a directory inside the `abydos-examples` repository. The
session restores a terminal sitting in it; the window follows its terminal;
`ProjectRoot.find(from:)` walks up to the git root and answers `abydos-examples`,
which is not the project that was just opened — so the window switches to it one
second after launch and restores *that* project's tabs over the ones it had. It
happens with `--file`, without `--file`, and with the project's own `.abydos`
moved away, so neither the session nor the argument parsing is the cause.
**Opening a project that is a subdirectory of a repository throws it away for the
repository, while the terminal that "moved" never moved.** That is a fault in
following the terminal rather than in this feature and is worth an item of its
own; it is written down here because it is why the measurements at the top of
this item found nothing wrong with a pane that was never on screen to be found.
It is also the second reason 0499 was watched green: the spike was not inside
another repository either.

Screenshots are in `images/`, all three against `abydos-examples/cadova-models`
or a byte-for-byte copy of it. `0507-before-empty.png` is the reported symptom
reproduced — Split Right, right half entirely blank, while the driver says
`state=failed said=…error: use of local variable 'spacing'…`.
`0507-failure-in-split.png` is the same run with the four lines in, showing three
diagnostics with file, line and column. `0507-model-in-split.png` is the model
beside its source, `runs=1 model=hex-key-holder.3mf`.

## Steps

- [x] Reproduce with the driver against the fixture, and make the driver agree
      with reality — a pane that exists must not be reported missing
- [x] `--cadova-watch` stops eating the argument after it, so a run that was
      given a file actually opens one
- [x] A negative answer from the driver says what *is* in front, and looks in
      every group rather than only the active one
- [x] Find why nothing appears: whether `whenShown` fires, and what the pane is
      showing when it does not
- [x] Fix it, and say in here which of the two candidates it was
- [x] The pane says what it is doing while it does it, including the first cold
      build
- [x] `drawn=` reports what the pane *paints*, not what its layout manager could
      lay out — the first version of this number could not tell the fault from
      the fix and is corrected above
- [ ] Watched against **this** fixture, not the spike, with a screenshot of the
      model in the split
- [x] A regression test that would have caught this — 0499's watching passed
      because it used a package with one target and no product rename
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does, if the behaviour it
      describes turns out to be wrong rather than just absent

The step about `drawn=` is found work rather than a bigger plan: the number was
added by the first pass as the instrument for this fault, and building it proved
it was not one.

**The first pass could run nothing.** Its sandbox refused every build, test and
app launch, and `/Users/philipparndt/dev/abydos-examples` was not readable from
it, so the fault was found by elimination against the screenshot. Everything it
concluded about the pane has since been compiled, run and photographed, and holds;
what it concluded about the two instruments around it did not, and is corrected
above rather than deleted.

## Ruled out, and other things found on the way

- **`whenShown` never firing.** The first candidate, and it is not it: the pane's
  initial notice is `Waiting to build hex-key-holder…`, `draw(_:)` shows a notice
  whenever there is no viewer, and a notice that was drawn is a notice the
  screenshot would have. It is ruled out by the *absence* of text rather than by
  its presence, which is the only reading of that screenshot that closes.
- **`cadovaPreview` / `cadovaPane(in:)` disagreeing with the view tree.** The
  second candidate, and there is nothing wrong with either. `makeTab` puts the
  pane in the split, the split is `tab.contentView`, and the recursive search
  finds anything in it. Two things disagreed with reality instead, one of them
  found by reading and one only by running: the *launch argument parser*, one
  function away from the driver, which advances its index before it knows whether
  it wanted to; and the window following its terminal out of the project
  altogether, which is measured above and is the one that produced the report in
  this item.
- **The pane being built into a group the driver was not looking at.** Guarded
  against anyway — the driver now asks every editor group rather than only the
  active one — but it is not what happened, and the honest report says so:
  `open=[Extrusion.swift]` was the whole of the *only* group. A negative answer
  that lists what is open is what turned a day of guessing into one line.
- **A layer-backed view swallowing `draw(_:)`.** Suspected, because
  `CadovaPreviewView` descends from `ColoredView`, which sets `wantsLayer` and
  overrides `updateLayer()`. It does not: `NSView.wantsUpdateLayer` is `false`
  unless a subclass overrides it, nothing here does, and `EditorDropView` — the
  other `ColoredView` that draws — carries a comment saying its drawing lands
  *behind* its subviews, which is a thing only a view whose `draw(_:)` runs can
  complain about.
- **Anything fixture-specific about detection.** Re-read rather than re-measured,
  since the item had already driven it from a test: `FilePreview.kind` returns
  `.model` for a `.swift` only when `PreviewFacts.isCadovaModel`, and that fact
  comes from the same `tab.cadova` the pane is built from — so a split that opened
  at all *had* to have a `CadovaPreviewView` in it. That is what forces the answer
  to be inside the pane.
- **The `Models/` subdirectory being the difference.** It is not the fault, and it
  did expose a real gap beside it: `CadovaRun.newestModel(in:since:)` was written
  against the spike, which wrote its `.3mf` beside the package, and carried a
  comment saying the package root "is where a model lands". `cadova-models` says
  `Project(packageRelative: "Models")`, so the fallback for a Cadova that words
  its line differently would have found nothing at all for this project's own
  fixture. It now looks one level down and never into `.build`.
- **Adding a unit test for the pane.** There is no test target for `AbydosApp` —
  `Tests/AbydosKitTests` is the only one, and view code is deliberately not in
  `AbydosKit`. So the regression test for *this* fault is the driver line
  (`drawn=`), which is the instrument the house already uses for panes; the
  unit tests added are the ones that can live in `AbydosKit`: the fixture's own
  manifest shape (two executable targets, one renamed by a product) and the
  fallback finding a model in a subdirectory. What makes `drawn=` a regression
  test rather than a decoration is that it was *run against the fault*: the
  unfixed pane prints `drawn=0x640`, the fixed one `drawn=533x640`, on the same
  fixture and the same broken source, so the line separates the two builds
  without anybody looking at a window.
- **Trusting a screenshot of the split.** 0499 recorded that `WindowCapture`
  composites the viewer's Metal snapshot at the pane's rectangle regardless of
  what is in front of it, and that is still true: the first capture here came out
  with the model drawn over a maximised terminal. `--panel-height 150
  --window-size 1400x900` is what makes the split photographable, and the driver
  line beside it is still the better evidence.
- **The terminal following, during a capture.** `terminalDirectoryChanged` already
  refuses to switch projects during a screenshot run, which is 0451's rule and
  the reason the three screenshots here could be taken against the real fixture at
  all. It is also what proves the switch is the cause rather than a coincidence:
  the same command with `--screenshot` keeps its Cadova pane and without it loses
  it.
- **A spec delta.** None. The step allowed for the spec being *wrong* rather than
  *absent*, and it was absent: `spec/previews.md` already promises that "a build
  that produces no model shows what the compiler said in place of the model
  rather than a shape that is not the one the code describes", and that sentence
  was aspirational for as long as the text view had no size. The requirement now
  describes what the code does, which is the point of it, so there is nothing to
  add and nothing to correct.

## Estimate

2026-08-16 18:10 — the fix is written; what is left is a build and one watched
run, which is under an hour for somebody who can run `make`
