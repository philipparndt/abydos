## Context

The 3D viewer is GoSTL's `MetalView`, hosted by `ModelContainerView` through
SwiftUI. On first use it makes a `MetalRenderer`, which loads its shader
library from `Bundle.module` — a `static let` SwiftPM generates for any target
with resources. The accessor Abydos gets is the plain-SwiftPM form:

    let mainPath = Bundle.main.bundleURL.appendingPathComponent("GoSTL_GoSTL.bundle").path
    let buildPath = "<absolute path into the building checkout's .build>"
    guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { fatalError(…) }

`mainPath` is the `.app` root, which holds `Contents` and nothing else;
`buildPath` is the builder's disk. It is a `static let`, so the abort cannot be
caught by whoever touches `Bundle.module`, and `MetalView` itself calls
`fatalError` when the renderer fails to initialise, so even a loader that threw
would still end the host.

AbydosKit solved the same fault for its own bundles in `ModuleResources`: a
list of directories tried in order — the main bundle's `Resources`, its root,
the bundle the code was loaded from, one level up from that for tests, and the
`Resources` of whatever `.app` the executable is inside — returning `nil` where
the generated accessor aborts. `Scripts/bundle.sh` copies every SwiftPM
resource bundle into `Contents/Resources`, compiles the GoSTL shader into a
`default.metallib` and writes it into both the app's copy and the build
directory's, and already refuses a build where the shader did not reach the app.

GoSTL is `philipparndt/gostl`, pinned `exact: "0.23.5"`, with a clone at
`~/dev/oss/gostl` that is behind the pin.

## Goals / Non-Goals

**Goals:**

- A model opens in an installed release on a machine that never built it.
- A viewer that cannot find its shaders is an empty pane with a message, not a
  dead process.
- A build on this machine can prove both without relying on the fallback that
  hid the fault.

**Non-Goals:**

- App Translocation of `/Applications/Abydos.app`. Real, and a consequence of
  the quarantine attribute the install work this morning is about; not the
  cause here.
- Replacing the generated accessor everywhere in GoSTL's *demo app* target,
  which Abydos does not link.

## Decisions

### 1. The fix is in GoSTL, and it is `ModuleResources` again

`loadShaderLibrary` stops reading `Bundle.module` first. It asks a small
`GoSTLResources.bundle` — the same search `ModuleResources` runs, anchored on a
class inside the GoSTL target so `Bundle(for:)` names the binary the module was
statically linked into — and falls back to `Bundle.module` only when that list
found nothing, which is the case where the generated accessor's build path is
the honest answer: a plain `swift build` on the machine that built it. The icon
lookup in `GoSTLApp.swift` goes through the same call.

*Ruled out: fixing it from Abydos.* Nothing outside the module can reach the
`static let` before it runs, and the two places it looks are not places a
signed `.app` can put anything.

*Ruled out: a copy or symlink of the bundle at the `.app` root.* It is what the
accessor's first probe wants, and `codesign` refuses an application bundle with
anything beside `Contents` at its root, so a release could not be signed.

*Ruled out: `PACKAGE_RESOURCE_BUNDLE_PATH`.* SwiftPM's Xcode-style accessor
honours it and this one does not; and an environment variable is not something
a Finder launch can be given.

### 2. A loader that cannot find the bundle throws, and the viewer shows nothing

`loadShaderLibrary` throws `shaderLoadingFailed` when no directory holds the
bundle, exactly as it already does when the bundle holds neither `.metallib` nor
`.metal`. `MetalView` stops calling `fatalError` on a renderer that failed to
initialise: it makes no renderer, draws nothing, and reports the error through
the same path the load failures already take — so the host sees the empty pane
and the message `previews` requires, and cannot tell this failure from a model
that would not render, which is what that requirement asks.

*Ruled out: keeping the abort as "cannot happen once decision 1 is in".* A
build assembled by hand can leave a bundle out — `bundle.sh` guards it, and
guards are for the day one does not run — and a process ending is never the
right report for a missing file.

### 3. Abydos asks before it makes a viewer

Before `ModelContainerView` hosts a `MetalView`, Abydos asks
`ModuleResources.locate("GoSTL_GoSTL", in: searchDirectories)`. If it is `nil`,
the pane shows *the 3D viewer's resources are missing from this build* in the
place a render error goes, and no viewer is made. One `fileExists` per model
opened, and the pin becomes a promise checked rather than a promise made.

*Ruled out: trusting the pin alone.* Decision 2 means GoSTL would report the
same failure itself; the check here is what lets Abydos say something in its own
words and never hand a viewer a device to draw with when there is nothing to
draw from.

### 4. Proving it means taking the fallback away

The fallback is why this was never seen, so the proof has to remove it. The
driven run moves `.build/<arch>/release/GoSTL_GoSTL.bundle` aside — the path
baked into this checkout's binary — opens a model on a scratch copy with
`--metal-shot`, and puts the bundle back whatever happens, in a `trap`. Before
this change that run dies where the report died; after it the shot shows the
model. A second run with the app's own `Contents/Resources/GoSTL_GoSTL.bundle`
moved aside as well shows the empty pane and the message, and the process
still ends by itself.

`bundle.sh` keeps its note about the build path, reworded to say what it now
knows: that the path is the builder's and the run above is what stands in for
every other machine.

*Ruled out: `strings`-checking the release binary for the build path.* The path
is still there after the fix — the generated accessor remains as the last
fallback — so its presence says nothing.

### 5. The release of GoSTL is the maintainer's

The GoSTL changes are made in `~/dev/oss/gostl` after pulling it up to the
pinned `0.23.5`, with a test for the lookup order, and committed there. Tagging
`0.23.6` and pushing it is publishing, which no agent here does; the pin bump
in `Package.swift` follows the tag existing on GitHub, and the change is not
finished until it does.

## Risks / Trade-offs

- **`Bundle(for:)` on a statically linked module** names the host executable's
  bundle, which is what is wanted in the `.app` and under `swift test` is the
  test runner — the same two answers `ModuleResources` already handles by trying
  its list in order.
- **A machine without the Metal toolchain** is unchanged: the bundle is found,
  `default.metallib` is absent, and the runtime compile of `Shaders.metal` runs
  as it does today.
- **The moved-aside bundle during the driven run** is restored by a `trap` on
  exit, so an interrupted run leaves the build directory as it was.

## Open Questions

None. What was measured goes under a dated heading here when the driven runs
have been made.
