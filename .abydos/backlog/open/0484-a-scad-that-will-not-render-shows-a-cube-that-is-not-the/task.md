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

## Steps

- [ ] A `.scad` that does not compile says so in the pane, and does not show a shape
- [ ] A machine with no OpenSCAD gets GoSTL's own install instructions, which are
      already written and are already reached
- [ ] A reload that *succeeds* still takes the previous message away
- [ ] Watched on both, cold
- [ ] Write down here what was ruled out on the way
- [ ] `spec/previews.md` says what the project now does
