# 484. A scad that will not render shows a cube that is not the model

Open a `.scad` with a syntax error in it. The model half shows **a cube**, correctly
lit, sitting on the build plate, with no message anywhere. Nothing says the file did
not compile. Somebody who did not write the file has no way to tell that the shape on
screen is not the shape their code describes.

Reproduced on `broken.scad`, two lines, an unclosed bracket:

    cube([1,2,3]
    // unclosed

and watched at 7 s and again at 16 s after the tab opened, so it is not an overlay
that arrives late. The screenshot is in `images/`.

**The same path covers a machine with no OpenSCAD installed**, which is the worse
case: `findOpenSCADExecutable` throws `openSCADNotFound`, that propagates out of
`AppState.loadFile`, and the catch in `loadFileOnStartup` does exactly what it does
for a syntax error. So somebody without OpenSCAD gets a cube rather than the
instructions GoSTL has written for them.

## Where it comes from

Upstream, in the pinned GoSTL 0.20.2, and it is a race between two of its own
handlers rather than a missing message. `App/ContentView.swift`:

    } catch {
        handleLoadError(error, isAutoReload: false)
        setupInitialState(loadTestCube: true)
    }

`handleLoadError` sets `overlayError`, which is what draws `ErrorOverlay` — and the
overlay is written, and good: for `openSCADNotFound` it says "OpenSCAD Not Installed",
gives `brew install --cask openscad` and links the downloads page. Then
`setupInitialState` loads the cube, and loading clears `appState.loadError`, and

    .onChange(of: appState.loadErrorID) { _, errorID in
        ...
        } else if errorID == nil {
            // Error was cleared (successful reload), dismiss overlay
            withAnimation(.easeInOut(duration: 0.3)) { overlayError = nil }
        }
    }

dismisses the overlay that was set one line earlier. The comment is right about what
it is for — a reload that succeeds should take the message away — and it cannot tell
that difference from a failure followed by a fallback.

## Why it matters more than it did

It has been here for as long as the embedded viewer has, and until now it was only
seen by somebody who had *asked* for a model preview and could read a cube as "that
did not work". **0483 made the split the default for a `.scad`**, so now every
half-typed OpenSCAD file shows a plausible cube beside the code that does not describe
it, without being asked. That is the one way this default can mislead somebody rather
than merely cost them a render.

## Worth deciding

- **Whose bug to fix.** The cleanest fix is upstream and is small: do not clear an
  overlay that was set by the load which is being fallen back *from* — either drop the
  `setupInitialState(loadTestCube: true)` in the failure path, or gate the clearing on
  the reload having actually succeeded. 0481 is already in the GoSTL fork.
- **Whether the fallback cube should exist at all in an embedded pane.** A window of
  its own with nothing loaded wants something to show; a pane beside a file that
  failed does not, and an empty pane with a message is the honest answer.
- **What Abydos could do without upstream**, and whether it is worth it. Nothing
  clean: `ContentView.EmbeddingOptions` carries a background colour, a menu-panel flag
  and a snapshot handle, and no way to hear that a load failed. 0483 considered
  refusing to split when `openscad` is absent and ruled it out — see that item — and
  it would not have helped the syntax-error case at all, which is the common one for
  somebody who does have OpenSCAD.

## What was found on picking it up

**Upstream fixed it, and this item did not have to write a line of Swift.** The
description above is written against GoSTL 0.20.2; this project has pinned
**0.22.0** since 60611c09, and that release is titled *"a recipe builds where it
cannot overwrite the project, and a failure is never a cube"*. The second half of
that title is this item. `App/ContentView.swift`:

    handleLoadError(error, isAutoReload: false)
    // Nothing drawn, rather than the test cube this used to fall
    // back to: a failure must not be able to look like a success
    // (0484). See AppState.showFailedLoad.
    appState.showFailedLoad(of: url, error: error)

`AppState.showFailedLoad` clears the model, keeps the file's name against a
triangle count of zero, keeps the error, and — the part that is more than a
deletion — **sets the file watcher up on a load that failed**. The overlay
promises "the file will auto-reload when the error is fixed", and before this it
was a promise nothing kept: the source URL was only recorded on success, so a
first load that threw was watching nothing. Now the repair is noticed, and the
reload that succeeds is what takes the message away.

The `loadErrorID` handler that this item blamed is **still there, unchanged**,
and it is right that it should be: every remaining place that clears the error is
a load that worked. What was removed is the fallback that made a failure look
like one.

Upstream also disagreed with one sentence of this item, and its account is worth
keeping. Driving 0.20.2, GoSTL found the overlay in fact *survived* the fallback:
loading a model does not touch `loadError`, and at startup `loadErrorID` was
still nil, so the `onChange` never fired. What was on screen was a cube **and** a
message, not a cube alone — the item saw a cube and no message because the
message is not in a screenshot at all (below). The race is real and needs only a
prior error to fire; it was not what produced the picture in `images/`.

Upstream carries `Tests/GoSTLTests/FailedLoadTests.swift` for all of it,
including a test that reads `ContentView.swift` and counts the call sites of
`setupInitialState(loadTestCube: true)`: exactly one, and not in a `catch`.

One line of this item is now wrong in a way worth noting: `ErrorOverlay` no
longer offers `brew install --cask openscad`. It offers
`brew install --cask openscad@snapshot`, because the stable cask is the 2021.01
release and somebody who followed the old advice installed something that fails
later, looking like a bad model rather than a stale OpenSCAD. That is 0434's
finding, arrived at upstream independently.

## What was watched here, and what could not be

Cold runs of a debug bundle against a throwaway project in the scratchpad, never
against a checkout under `~/dev` — a driven run keeps its preferences in memory
now (0522), so this cost the machine nothing. The three pictures are in
`images/`, beside the original.

- **A `.scad` that does not compile.** The same two lines the item reports, split
  by default since 0483. `ERROR: Failed to load file on startup: renderFailed(…
  Parser error: syntax error … line 4)` on the console, and the model half draws
  **nothing** —
  `images/a-scad-that-will-not-compile-shows-no-shape.png`, which is the same
  window as `images/broken-scad-shows-a-cube.png` with the cube gone.
- **No OpenSCAD.** Reproduced without touching the machine, which is what made it
  observable at all: `sandbox-exec` denying `file-read*` on
  `/Applications/OpenSCAD.app` and `/opt/homebrew/bin/openscad` for that one
  process. `InstalledOpenSCAD.locate()` then finds none of its four paths and
  `which` finds none either, and the console says `ERROR: Failed to load file on
  startup: openSCADNotFound`. The pane draws nothing —
  `images/no-openscad-shows-no-shape.png`. It is `good.scad`, the very file that
  draws a cube when OpenSCAD is reachable, so the empty pane is the tool being
  missing and not the file being wrong.
- **A repair.** `broken.scad` opened failing, then rewritten on disk to
  `cube([30,10,5]);` while the pane was up: `reloadModel called` →
  `Model reloaded successfully!`, and the pane shows a 30×10×5 slab —
  `images/a-repair-brings-the-model-back.png`. The shape on screen is the shape
  the code describes, which is the whole claim, and `Model reloaded successfully!`
  is printed from the one branch that sets `loadError = nil; loadErrorID = nil`,
  which is what dismisses the overlay.

**What could not be observed: the message itself.** `--screenshot` cannot show
it, structurally and in two independent ways. GoSTL's snapshot provider renders
the *scene* offscreen — Metal only, no SwiftUI — and `WindowCapture.drawSnapshots`
then paints that image over the whole of `ModelContainerView` *after*
`cacheDisplay`, so anything the hosting view drew there is painted out. So no
screenshot can prove `ErrorOverlay` is on screen, and none can disprove it
either. What is settled is everything a screenshot *can* settle: the shape. A
failure now draws nothing, and nothing cannot be mistaken for a model.

Two things stand in for the picture. The console line proves which branch ran,
and `handleLoadError` sends both `OpenSCADError.renderFailed` and
`.openSCADNotFound` to `overlayError` rather than to the modal `errorAlert` —
only a non-OpenSCAD, non-go3mf error takes the dialog. And a dialog would have
been visible: `WindowCapture` writes sheets and child windows beside the capture
as `-sheet.png` and `-child0.png`, and neither run produced one.

## What was ruled out

- **Fixing it here.** Not attempted, and it would have been wrong twice over: the
  pane is GoSTL's, and 0.22.0 already does it. The Abydos side is unchanged by
  this item — `makeModelView` hands the URL to `ContentView` and
  `EmbeddingOptions` still carries only a background colour, a menu-panel flag
  and a snapshot handle, exactly as the item said.
- **Touching `~/dev/3d/gostl`.** A separate repository, and not this item's to
  edit. The fix arrived through the pin.
- **An Abydos-side notice, the way `CadovaPreviewView` has one.** That pane is
  ours and can say what the compiler said; this one is not, and a second message
  layered over GoSTL's own would be two accounts of one failure. The comment at
  `CadovaPreviewView.swift:379` already draws that line and names this item.
- **Uninstalling OpenSCAD to see the not-found case.** Refused outright — a
  machine is not a fixture. The sandbox denial above gets the same code path for
  one process and leaves the machine as it was.
- **A `--model-watch` instrument, the way 0499 and 0512 built one.** Considered
  for reading `overlayError` out of a running pane, and not built: the state it
  would report lives in GoSTL's `ContentView`, which is `internal` to that module
  and not reachable from `AbydosApp` at all — the instrument would have to be
  written upstream, for a claim upstream already holds with a unit test.

## Estimate

2026-08-17 14:13 — about half an hour left

## Steps

- [x] A `.scad` that does not compile does not show a shape — fixed upstream in
      GoSTL 0.22.0, watched here. The *message* it shows beside that is upstream's
      `ErrorOverlay` and cannot be photographed through the Metal snapshot; the
      reasons it is nonetheless reached are written above
- [x] A machine with no OpenSCAD gets GoSTL's own install instructions, which are
      already written and are already reached — the path is reached, shown by
      denying the four locations to one process; the panel itself is the same
      unphotographable overlay
- [x] A reload that *succeeds* still takes the previous message away
- [x] Watched on both, cold
- [x] Write down here what was ruled out on the way
- [x] `spec/previews.md` says what the project now does
