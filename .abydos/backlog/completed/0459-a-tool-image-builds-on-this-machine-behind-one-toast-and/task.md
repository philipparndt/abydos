# 459. A tool image builds on this machine behind one toast and silence

Reported from use: choosing to build a language server's image here — 0434's
route, and 0457's kmp-lsp is the first one anybody would pick it for — shows one
toast and then nothing at all while the build runs.

0457 measured that build cold at **164 seconds**. `openscad-lsp` and kmp-lsp are
both Rust: a compiler, a registry fetch, and minutes. From the outside, minutes
of silence after a toast is indistinguishable from a feature that did not work,
which is the sentence already written above the `progress` closure in
`LanguageService`:

    // A pull with nothing on screen is indistinguishable from a
    // feature that does not work.

That comment is about a *pull*, and a pull is seconds. A build is minutes and got
the same treatment.

## What is actually missing, and it is one argument

`ContainerImageStore.ensure` already takes both halves:

    progress: (@Sendable (String) -> Void)? = nil,     // one sentence before it starts
    onOutput: (@Sendable (String) -> Void)? = nil      // the build's own output, as it arrives

`LanguageService` passes `progress` and **not** `onOutput`. So the sentence
arrives and the four minutes of `docker build` go nowhere. `ProcessPipes.drain`
grew `onOutput` for exactly this and says so in its own note — "a `docker build`
that takes four minutes is four minutes of nothing at all if its output only
appears at the end".

## The devcontainer path already solved this

`DevContainers` passes `onOutput:` into the build and the output lands in
`PreparingTerminal` — a tab that opens at once, has the work written into it, and
then *becomes* the shell, keeping the scrollback. 0444 added the same for the
language-server path when a *devcontainer* comes up, deliberately not taking the
keyboard, opening the panel only if the start is still going after three seconds,
and taking its tab away again if nobody could have watched it.

**All of that applies unchanged to a tool image build.** This item is mostly
routing an existing pane at an existing stream, and the decisions 0444 already
made — no keyboard, open late, tidy up after a fast one — should be taken rather
than made again.

## Worth deciding

- **Whether every image build gets a pane, or only a slow one.** A pull of a
  cached image is instant and a pane for it is noise. 0444's three-second rule is
  the precedent and probably the answer.
- **Where a failed build's output goes.** Today a failure is a toast with a
  reason, and `ToolImageRecipes` has a four-way explanation — runtime down, no
  network, registry refused, no disk. With a pane, the pane *is* the error and
  the toast should point at it rather than try to summarise a hundred lines of
  compiler output. Same decision 0444 recorded.
- **The other three callers.** `PlantUMLPreviewView`, `DiagramExport` and
  `DevContainers` all call `ensure`. The first two pull rather than build today,
  but a recipe can be written for anything, so whatever this does should not be
  wired only into `LanguageService`.

## Ruled out

Worth knowing rather than rediscovering: the build output already crosses the
process boundary correctly. `ProcessPipes.drain` reads both pipes on threads of
their own precisely so a chatty build cannot deadlock against a full pipe, and
`drainText` decodes a piece at a time, which is why a multi-byte character split
across two reads comes back as a replacement character in the piece and not in
the whole. That held: nothing in the pipeline needed touching.

**A tab made when the image is asked for, rather than when the runtime says it
has work.** That is what the devcontainer route does — 0444's pane is made
before anything is started — and copying it here would have been a terminal
pane, a session, a wired strip and a notification made and thrown away on every
project open and every diagram, because `ensure` answers `.present` in
milliseconds for every use after the first. The two are not the same shape: a
devcontainer start always *is* a start, and getting an image usually is not.
The first sentence is the runtime admitting it has minutes of work, so that is
where the pane begins.

**Revealing a failed build's pane only when it printed something.** Considered,
because a runtime that is not running produces one sentence and a pane holding
one red line with a toast pointing at it is worse than the toast alone. Dropped
on looking: `docker build` against a dead daemon writes its complaint to a pipe
like everything else, so "has output" is true in every case and the rule
degenerates to "always". The pane is revealed whenever a build fails, as 0444
already decided for a container.

**Summarising the failure in the toast and leaving the sentence out of it.**
That is 0444's rule and it is not taken here, deliberately.
`ToolImageRecipes.explain` produces a *diagnosis* and not a summary — four of
its five answers are complete, and somebody who reads "there was no room to
build openscad-lsp" in the corner is finished. So the corner carries the
sentence *and* names the tab, and the tab is for the fifth answer, where the
reason is one line somewhere in a hundred of compiler output.

## Estimate

2026-08-11 09:23 — about twenty minutes left — the work is done and driven, the item and the spec are written

## Steps

- [x] `LanguageService` passes `onOutput` as well as `progress`
- [x] The output lands in a pane, on 0444's terms — no keyboard, opened only if
      the work is still going after three seconds, and its tab taken away if
      nobody could have watched it
- [x] A failed build leaves its output where somebody can read it, and the toast
      points at the pane rather than summarising the compiler
- [x] The other callers of `ensure` get the same treatment, not just this one
- [x] A pane that is only ever a report is not written into `.abydos/session.json`
      — found on the way, and the same fault 0444 fixed for the devcontainer tab
- [x] A pane written into while it is hidden keeps a real width — found by
      photographing it, and the reason the first picture was four hundred lines
      of build log in a twenty-character column
- [x] A build is not called a fetch anywhere on screen: not in the tab, not in
      the toast, and not in the strip above the file
- [x] Tests the kit can reach: the name test that says build or fetch, and a
      build proving the output arrives while it runs rather than at the end
- [x] Driven with a recipe that really builds and a cold cache — `openscad-lsp`
      through the app, on an image builder that had just been restarted
- [ ] The same through the gated live test,
      `ABYDOS_BUILD_TOOL_IMAGES=1 xcrun swift test --filter BuiltToolImageLiveTests`.
      Not done, and not for want of trying: that suite takes
      `discover(preference: .automatic)`, which prefers docker, and docker's
      daemon is down on this machine — so `ensure` fails in half a second
      against a runtime that is not answering. It still skips itself in a plain
      `make test`, which is the part that had to stay true, and does
- [x] Write down here what was ruled out on the way
- [x] `spec/tool-images.md` says what the project now does

---

## What was built

**One argument, and then four things the argument uncovered.**

`ImageArrival` is the whole of the wiring: it hands `ensure` the two sinks it
has always taken, and it opens `PreparingTerminal` — the pane the devcontainer
path already uses — to put them in. `MainWindowController` makes that pane in
one method now rather than two, because the terms are one decision and not two
that happen to agree: no keyboard, ever; the panel opened only if the work is
still going after three seconds; a wait nobody could have watched takes its tab
with it. All three are 0444's, taken unchanged.

**Every image gets a pane, and almost none of them gets a tab.** The pane is
made at the runtime's *first sentence* rather than when the image is asked for,
which is the one place this differs from the devcontainer route and is the
answer to the question the entry asked. `ensure` says nothing at all when the
image is already on the machine — every use after the first — so nothing is
made, and a fetch quick enough that nobody saw it takes its tab away again.

**Three endings rather than two.** A devcontainer's pane becomes a shell; a
build leaves an image and nothing to attach to. `finish` is that ending: it
keeps what was printed under one green line, or takes the tab with it if the
pane was never revealed. `isDone` is what the three-second reveal waits on now,
since `isShell` would have opened a panel three seconds after a build had
already finished and tidied itself away.

**A failed build: the pane is the log and the corner is the diagnosis.** The
reason goes in the pane in red under everything the build said, the panel opens
at once, and the toast carries the sentence *and* names the tab. That last part
is where this parts company with 0444 deliberately — see "Ruled out".

**And four places that called a build a fetch**, which is the conflation 0434
gave `ToolImageRecipes.progressMessage` its own sentence to avoid, still being
made everywhere else:

- the failure said "*rust-analyzer* could not be **fetched**" of something no
  registry has;
- the strip above the file said "its language server is being **fetched**"
  while a compiler ran;
- the tab had to say which, so it does: *Building* openscad-lsp against
  *Fetching* PlantUML, from `ToolImageRecipes.isBuiltHere`, which is the
  namespace test and not a directory walk;
- and the names in the corner and on the tab are now the tool's `name` rather
  than its `command`, so "Building pyright" is not "Building
  pyright-langserver".

### Two faults found by driving it that reading it would not have shown

**A pane written into while it is hidden was twenty columns wide.** The first
photograph of a failed build is four hundred lines of `docker build` wrapped
into a twenty-character column down the left of a full-width pane.
`recomputeGridSize` measures the clip view, a tab that is not in front is never
laid out, and `max(20, …)` is what a width of nothing answers. Harmless for a
shell, which is told its size when it starts; permanent for a pane being
written into, because scrollback does not reflow. It now declines to resize when
there is nothing to measure, and keeps the eighty columns it was made with.

**A pane that is only ever a report was written into `.abydos/session.json`.**
Every terminal in the panel is remembered and opened again next time, and a
build's pane never becomes a shell — so the tab somebody kept in order to read
it would come back every session as a prompt called "Building rust-analyzer".
That is 0444's accumulating-tabs fault from a second direction; `captureTerminals`
now skips a pane with no process in it, which also stops `☸ launch` and a pod's
output coming back as shells.

## What was seen

Driven through the app, on Apple's `container` — docker was down on this machine
all morning, see below — with the panel asked what it held at each of several
seconds, because the tab is deliberately not on screen when it is made and a
screenshot proves nothing about it.

- **A build, cold.** `openscad-lsp`, which had never been built here, with the
  image builder restarted first so nothing was cached: **2s** `*tmux | Building
  openscad-lsp` — the tab exists and is *not* in front; **4s** `tmux | *Building
  openscad-lsp` — the panel has opened itself and the tab has come forward;
  **10s** through **60s** the pane filling with `#7 … Compiling icu_provider
  v2.2.0`, `Compiling lsp-server v0.7.9` as `cargo` got to them; **~53s**
  `abydos-built/openscad-lsp:32c86f523478` and, in green, `openscad-lsp is built.
  Nothing else will build it until its recipe changes.`; the server initialised a
  moment later and at **100s** the strip had stopped saying anything.
  `images/a-build-in-the-panel.png` is the middle of one.
- **The strip while it happens**, read at 5s and 30s: *"OpenSCAD's language
  server is being built on this machine. It happens once, and the terminal panel
  shows it happening."* It said "is being fetched" before this item.
- **The keyboard.** `FOCUS … NSWindow` at every reading of every run, and never
  a terminal view. Weaker than 0444's `CodeView` and worth saying so: a capture
  run never becomes the key window, so what is proved is that the pane did not
  take the keyboard, not that the editor kept it. The caret is in the editor in
  both pictures.
- **A build that fails.** The bundled `pyright` recipe pinned to a version npm
  does not have. The pane keeps the whole of it — the apt layer, `npm error
  notarget No matching version found for pyright@1.1.99999`, the `------` and
  the solver's own line — and then, in red, *"Building pyright failed: … The
  recipe is …/ToolImages/pyright/Dockerfile."* In the corner, at 6s:
  **pyright could not be built** / the same sentence / *"What the build printed
  is in the Building pyright tab in the terminal panel."* When the failure came
  inside three seconds the panel opened at once rather than waiting for the
  timer. `images/a-build-that-failed.png`.
- **The warm case leaves nothing.** The same Rust project with its image already
  on the machine: `PANEL: visible=true *tmux` at 2, 5 and 10 seconds, `TOASTS:
  (none)` throughout, and the server started from `abydos-built/rust-analyzer:d409fd8bc582`
  a second in. No tab was made at all.
- **The session file.** Read after a run that ended with a build's tab open and
  read: `terminals` holds `tmux` and nothing else.

**The reported case itself** — `rust-analyzer` from `.abydos/tools.json` saying
`{"rust-analyzer": "build"}` — was driven with its image deleted first, and
behaved as above: tab at 2s, panel at 4s, the export layers streaming, the green
line. It is **not** the 164 seconds 0457 measured, and that is the honest
qualification on this whole entry: deleting an image does not delete the
builder's layer cache, so the rebuild was seconds. The minutes-long case was
reproduced with `openscad-lsp` on a builder that had just been restarted, which
is a real cold build of a real recipe and the same code path.

## Not proved, and left out

- **Nothing here is unit-tested above the kit.** `LanguageService`,
  `MainWindowController`, `PreparingTerminal` and `ImageArrival` are in a target
  the suite cannot reach, which is the wall 0433, 0438 and 0444 all hit. What
  the suite does cover is the claim the pane exists for — that a build's output
  arrives while it is still building — and the name test the tab's wording turns
  on. Everything under "What was seen" is covered by having been watched.
- **`PlantUMLPreviewView` and `DiagramExport` were wired and not driven.** No
  recipe ships for a diagram tool today, so both still only ever pull, and the
  pane they would open has been read rather than seen. `DiagramExport` is the one
  that needed a third sink — it fetches an image and then draws several pictures,
  so its one returned value cannot say which half failed.
- **The three-second delay is still a judgement**, as 0444 said. It was watched
  letting a warm start pass unseen and revealing a build's first minute, on one
  machine.
- **A build that is still going when the project is closed** was not tried. The
  pane's weak reference and `wasClosed` are 0444's and untouched.
- **Docker was down on this machine all morning**, its CLI on the path pointing
  at an OrbStack socket that does not exist, and it costs two things here.

  `ContainerImageLiveTests`' two `preference → .docker` cases fail: `docker
  image inspect` answers *"failed to connect to the docker API … no such file
  or directory"*, and `isUnknownImage` quite correctly declines to call that a
  missing image. The `.apple` case of both passes, and `RuntimeCommand`,
  `ContainerRuntime.discover` and `isUnknownImage` are byte-identical to `main`.

  And `BuiltToolImageLiveTests` cannot be run at all: it takes
  `discover(preference: .automatic)`, which prefers docker, so with
  `ABYDOS_BUILD_TOOL_IMAGES=1` it asks a dead runtime to build and is told no in
  half a second. Without the variable it skips itself, which is what matters for
  `make test` and is what it did.

  Both are the same hole and it is not this item's: a live test skips when the
  *binary* is missing and not when the *daemon* is, and a suite that has to pick
  a runtime picks the one that is installed rather than the one that answers.
  Worth an item of its own rather than a change made in passing here.
