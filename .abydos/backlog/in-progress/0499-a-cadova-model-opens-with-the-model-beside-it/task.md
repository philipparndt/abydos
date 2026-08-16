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

## What was decided, and what it cost

### 1. Which tabs get a model beside them: the sources of a Cadova executable target

Not "a `.swift` file" — nearly every `.swift` ever written is not a model, and a
default that split them all would make opening any Swift project feel broken.
Not "a file with `Model(` in it" either, which was the tempting cheap answer and
is wrong in both directions: a model can be built in a function in another file,
and a helper file with no `Model(` in it changes the shape exactly as much as
the entry point does.

**The manifest is the only place that says Cadova out loud**, so that is what is
read, and the unit is the *target*, because a target is what gets built and run.
`CadovaModel.find(for:stoppingAt:)` walks up from the file to `Package.swift`,
finds the target whose sources contain the file, and answers yes when that
target is an `.executableTarget` whose `dependencies:` mention `Cadova`. Three
things fall out of that and all three are tested:

- **A library target that uses Cadova is not a model.** It is not run, so there
  is no shape to show.
- **An executable target that does not use Cadova is not a model.** It is a
  program.
- **`Package.swift` is not a model of its own package**, which a `path: "."`
  target would otherwise have made it.

Reading targets at all meant `SwiftPackage` growing: it held `(name, line)` per
*runnable product* and nothing about dependencies or where sources are. It now
reads `.target` as well as `.executableTarget` and `.testTarget` — which looks
dangerous, because `.target(name: "Shapes")` is also how a dependency on a
sibling target is written, and is safe because of how the scanner moves: a
matched call consumes to its own closing parenthesis, so a `.target(…)` inside
another target's `dependencies:` is walked past rather than read as a
declaration. There is a test for exactly that.

**What it costs to ask.** One walk up the directories and one read and scan of
the manifest, per tab, for a `.swift` file. Nothing at all for any other
extension, and nothing when there is no package. Decided once when the tab opens
and kept on the tab, the same rule and for the same reason as
`Tab.looksLikeRecipe`: the tab bar asks what modes a file has on every refresh,
and a refresh follows a keystroke.

**And it opens split, without being asked.** The `.scad` argument from 0483
holds and is *stronger* here, which was the surprise. OpenSCAD renders on the
main actor, so 0483's 200–340 ms is 200–340 ms of window that does not draw;
`swift run` is a subprocess, so even the 46 s cold build costs no frames at all.
What it costs instead is SwiftPM's exclusive lock on `.build` — a preview build
makes the user's own `swift build` in a terminal wait, and the other way round.
That is named rather than designed around: two builds of one package contending
is the same wait two terminals would have.

The go3mf answer stays different and the difference is still not arbitrary. 0482
opens a recipe as text because *whether a `.yaml` is a recipe at all* was decided
by reading the head of the file, and a default that starts minutes of rendering
off a guess about contents is dangerous. Nothing is guessed here: the manifest
names Cadova.

### 2. Where the 3MF is: read out of what the run said

Cadova names the file after the model *inside the code* — `Model("hexholder")`
writes `hexholder.3mf` — so the path cannot be known in advance. The item
offered two candidates and called watching "more honest". **Parsing wins, on an
argument the item did not have: the output is captured anyway.** A run that
fails has to reach the person, which means reading both pipes; given that,
picking a line out of what was already read costs nothing, and it names the file
exactly where a watch would have to filter everything `swift build` writes into
the same tree.

Measured from the spike, on stdout, and this is the whole of the contract:

    2026-08-16T11:47:03.401 [INFO] Wrote model to /…/cadova-spike/hexholder.3mf

Absolute, so nothing has to be resolved against anything. The last such line
wins, for a target that writes more than one.

`CadovaRun.newestModel(in:since:)` is the fallback for a Cadova that words the
line differently: the newest `.3mf` beside the package, modified since the run
began. **This is not the watcher that was rejected** — it is one directory
listing after a run that has already ended, rather than a stream of events to
filter for as long as a pane is open.

### 3. How often: on a source file changing on disk, and never on a build

On **disk**, not on a keystroke and not on this tab's document, and each half of
that is deliberate. The compiler reads the disk, so building an unsaved buffer
would show the shape of the last save while claiming to show this one. And the
tab's own document is one file of a target that may have several, where a
`git checkout` is a change too — so it is `FileSystemWatcher` over the target's
source directories, which was already in the codebase with 0.25 s of coalescing
built in, plus the house 0.4 s debounce on top.

**Two things had to be found by watching it in the app, and both are the sort of
thing that reads as intermittent:**

**A build triggers a rebuild.** FSEvents with `kFSEventStreamCreateFlagFileEvents`
reports a file's inode metadata changing, and *compiling a file changes its
access time*. So the first version rebuilt because it had just built: watched at
14 s into a run with nobody touching anything, a second `swift run` started. The
fix is that the watcher now says *look* and
`CadovaModel.sourceFingerprint()` says *whether anything changed* — the
modification date and size of the target's `.swift` files, one `stat` each,
taken at the moment a run starts so that everything the build touches from then
on is the build's own doing. A test writes a file and reads a file and asserts
the difference.

**A `swift build` cannot be cancelled, and killing one corrupts `.build`.** The
item asked for the previous run to be *cancelled*, which is what a diagram pane
does to a JVM, and it is wrong for a package build. `process.terminate()` stops
the shell and not `swift-build` and its frontends, so the killed build carried
on writing `.build` while its replacement wrote it too. What that produced, in
the app, twice:

    …/.build/out/SDKExplicitPrecompiledModules/std_errno_h-3NG94XJO41M1N6Q94E00XNRXU.pcm
    not found: module file not found

and then **five consecutive cold builds** — 46 s, 53 s, 54 s — while SwiftPM
rebuilt what had been half-written; one recovery build measured 73 s. That is
the loop above and this fault feeding each other, and it is why the timings in
the first half of this item's watching were nothing like the spike's.

So a change arriving during a build is **remembered and honoured when the build
ends**, rather than killing it. It coalesces a burst of saves into exactly one
extra run — the outcome cancelling was for — by a means that does not corrupt
anything. The one place a build is still killed is the pane's `deinit`, and that
is a knowing trade: an orphaned build nobody is waiting for, holding the lock
and a dozen `swift-frontend` processes, is worse than one cold rebuild.

The step below still reads "and the previous run is cancelled" and is ticked,
because what somebody sees is what it promised — a burst of saves is one
rebuild. The mechanism is not cancellation, and this paragraph is why.

### 4. A run that fails: the compiler takes the model's place

0484's complaint is a plausible shape on screen that nobody's code describes,
with no message anywhere, and it is unfixable from here because that pane is
GoSTL's. This pane is ours, so the honest thing is available: on a failure the
model **goes**, and the diagnostics are shown in its place, in a monospaced,
selectable, scrollable text view — selectable because the point of showing the
compiler rather than summarising it is that the line somebody wants is one they
will paste.

Keeping the last good shape under a failure banner was the alternative and it
was rejected: it is the same lie with a caption. The cost is that a save with a
syntax error in it takes the model away until it compiles, and that is the right
way round — it is a state you want to know about.

**Choosing which lines** took a watch to get right. The first version showed
every line containing `error:`, and what the pane led with was

    error: SwiftCompile normal arm64 failed with a nonzero exit code. Command line:     cd /private/tmp/…

— the build system announcing that a compile failed, true and useless, with the
diagnostic that matters four lines below it. So the order is now: lines that
name a *place in a file* first (`…/main.swift:6:24: error: use of local variable
'spacing' before its declaration`), any other `error:` line when there are none
of those, and the tail of the output when nothing said `error:` at all — which
is 0498's warning honoured, that "no model appeared" must never be reported as
anything but what it actually said. Left out either way: the box-drawn source
context, which a narrow pane cannot lay out, and the `swift-frontend` command
line, which on this machine is one line of four thousand characters.

**SwiftPM colours its diagnostics down a pipe.** Measured, not assumed — the
escape codes are there whether or not it is talking to a terminal, so the pane
would have shown `[0;36m` in front of every line. `CadovaRun.stripped` is why it
does not.

## What was watched

`--cadova-watch <seconds>` prints what the pane in front is doing, once a
second: the state, the file the viewer has, how many runs have finished and the
last line of the build. Over time, because the claim is a *sequence* — a single
reading cannot tell a pane that just built from one that was showing a model all
along. `--run-config` from 0498 watches a run; this watches a pane.

**Opening the file, then changing a constant and saving** (`height` 12 → 30),
against a warm build directory:

    0s   state=building runs=0 model=none    said=(eval):1: can't change option: zle
    5s   state=building runs=0 model=none    said=[Writing build description]
    6s   state=model    runs=1 model=hexholder.3mf
    …    steady for twelve seconds, and no second run
    18s  state=model    runs=1 model=hexholder.3mf  said=Building spike…
    31s  state=model    runs=1 model=hexholder.3mf  said=[7 / 8] spike-product
    32s  state=model    runs=2 model=hexholder.3mf
    …    steady for twenty-eight seconds

Three things in that. The model appears **6 s** after the file is opened. The
twelve quiet seconds are the fingerprint doing its job — before it, that gap was
another build. And the rerun is `[7 / 8]`, an incremental build of eight units
rather than the 526 a corrupted `.build` costs. `hexholder.3mf` is rewritten in
place, so GoSTL's own file watcher reloads it and the camera is not thrown away
— which is the point, since turning the part round to look at the change is the
work.

**Breaking the file, and repairing it** (`let spacing = 8.0 +`):

    6s   state=building runs=0 model=none
    7s   state=failed   runs=1 model=none
         said=…/Sources/spike/main.swift:6:24: error: use of local variable 'spacing'
              before its declaration
    …    steady for twelve seconds
    20s  state=building runs=1 model=none  said=Building spike…
    26s  state=model    runs=2 model=hexholder.3mf

**And a `.swift` that is not a model**, opened from this repository — a Swift
package with four executable products, none of which uses Cadova:

    CADOVA: 0s no cadova pane in the tab in front   (and so on, for six seconds)

**Timings, honestly.** A warm rerun is 6–13 s of wall clock from the save to the
new model, of which the build itself is 1–3 s: `swift run` re-checks the
manifest and the resolved dependencies every time, and the login shell adds
0.17 s. The item's "about two seconds" is SwiftPM's own `Build complete!`
number and is not what somebody waits. A cold build is 46–54 s, as measured,
and the pane says what it is doing throughout — the last line of the build,
because a pane that says only "Building…" for most of a minute is
indistinguishable from a pane that has hung.

## Ruled out, and other things found on the way

- **Watching the package directory for the `.3mf`.** Ruled out for the reason in
  decision 2, and there is a second one: the directory the model lands in is
  also the one `swift build` writes thousands of files into.
- **Watching the tab's own `TextDocument` for saves.** `onAutoSaved` is a single
  closure and `EditorViewController` already owns it, so a pane would have had
  to take it away or `TextDocument` would have had to grow a list of observers —
  and it would still only have heard about *this* file, where a target has
  several and any of them changes the shape.
- **A second `Bool` parameter on `FilePreview.kind(for:looksLikeRecipe:)`.**
  There were six call sites and every test passing the first one; a second
  boolean is a seventh argument at all of them, and the fifth call site is the
  one that forgets. `PreviewFacts` is one value that grows without touching a
  caller that does not care.
- **Adding `swift` to whatever triggers a rescan.** Not needed here, and 0498
  already ruled it out for the run list with 0446's 668 seconds behind it. The
  fact is decided per tab, when the tab opens.
- **Copying `ModelContainerView`'s "on screen for `startAfter`" guard.** It is
  extracted into `DelayedPaneView` instead, so a Cadova pane starting a package
  build gets the same rule as an OpenSCAD pane starting a render, from the same
  code. A walk down a directory of models still starts nothing.
- **`swift build` instead of `swift run`.** Would need a second step to run the
  product and a way to find the binary, and buys nothing: `swift run` on an
  unchanged package is `Build complete! (1.07 sec)`.
- **A screenshot of the split.** Taken, and it shows the model rendering
  correctly — but with the terminal tool window covering the editor, and the
  model drawn *over* it. That is `WindowCapture` compositing the viewer's Metal
  snapshot at the pane's rectangle regardless of what is in front of it, and it
  reproduces **identically with a plain `.3mf`** on the untouched code path, so
  it predates this item and is not filed under it. The driver output above is
  the better instrument anyway: a model cannot be read off a screenshot and a
  build cannot be photographed halfway through.
- **Two panes on the same package.** Not guarded against. Both would run, and
  SwiftPM's lock serialises them and says so in the output the pane is showing.
  A guard would be a second scheduler for a case nobody has hit.
- **A package that gains a Cadova dependency while a file of it is open.** Stays
  text until the tab is reopened, which is `looksLikeRecipe`'s trade one size
  larger. The alternative reads a manifest on every tab-bar refresh.

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
- [x] A build or run that fails says so where somebody will see it
- [x] A driver that reports what a Cadova pane is doing, so it can be watched
- [x] Watched in the app: open a Cadova model, see geometry, change a constant,
      save, watch it change
- [x] Write down here what was ruled out on the way
- [x] `spec/previews.md` says what the project now does

The four new steps were found work rather than a bigger plan: the first two are
`SwiftPackage` not yet being able to map a *file* to a target (it holds
`(name, line)` per runnable product and nothing about sources or
dependencies), the third is `FilePreview.kind(for:looksLikeRecipe:)` needing a
second fact of the same shape at six call sites, and the fourth is that
`--run-config` from 0498 watches a *run*, and what has to be watched here is a
*pane*.

## Estimate

2026-08-16 15:05 — done
