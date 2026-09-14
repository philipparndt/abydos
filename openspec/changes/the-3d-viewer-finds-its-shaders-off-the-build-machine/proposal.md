## Why

The maintainer, 2026-09-14, with a crash report: Abydos 0.21.0 (2031), five
and a half hours into a session, died with `EXC_BREAKPOINT` the moment a 3D
model was opened. The top of the stack is

    _assertionFailure
    closure #1 in variable initialization expression of static NSBundle.module
    MetalRenderer.loadShaderLibrary(device:)
    MetalView.makeNSView(context:)

That is SwiftPM's generated `Bundle.module` accessor for the GoSTL package,
aborting because it could not find `GoSTL_GoSTL.bundle`. The accessor tries two
places and no more: `Bundle.main.bundleURL/GoSTL_GoSTL.bundle` — the root of
`Abydos.app`, beside `Contents`, where no packaged app keeps anything — and a
path hard-coded at compile time into the build directory of the machine that
built it. The installed binary carries

    /Users/philipparndt/dev/abydos/.build/arm64-apple-macosx/release/GoSTL_GoSTL.bundle

which does not exist on this machine, whose checkout is
`/Users/Philipp.Arndt/dev/oss/abydos`. So the bundle is never found, and the
first model opened takes the process down — in every copy of every release run
anywhere but the machine that built it, which is every user.

It never showed on the build machine because the fallback path exists there.
`Scripts/bundle.sh` has said so for some time — "`Bundle.module` resolves to the
build path whenever it still exists, which it does on the machine that built
the app" — without drawing the conclusion. `ModuleResources` in AbydosKit exists
for exactly this fault in this package's own targets, and its rule is *never
`Bundle.module`*; GoSTL is the one dependency still calling it, and it is the
maintainer's own package.

There is no originating `.abydos/backlog` item: this comes from the crash
report above.

## What Changes

- **GoSTL finds its resource bundle the way `ModuleResources` does**: the main
  bundle's `Resources`, then the bundle the renderer's own class was loaded
  from, then beside the executable and at the bundle root, and only then the
  generated accessor. Both call sites — the shader loader and the app icon —
  go through it. When nothing is found the loader **throws** rather than
  aborting, and the viewer shows no model and says why, which `previews`
  already requires of a render that fails.
- **Abydos pins the release of GoSTL that has this**, and asks before making a
  viewer whether the bundle can be found at all, so a build assembled without
  it shows the message in the model pane instead of asking a viewer to draw
  with nothing.
- **The build proves it without the fallback.** A driven run opens a model with
  the build directory's copy of the bundle moved aside, so the only way to the
  shaders is the one an installed release has.
- **Not in scope**: App Translocation. The crashed copy and the one running now
  are both under `/private/var/folders/…/AppTranslocation`, because
  `/Applications/Abydos.app` carries a Safari quarantine attribute. It did not
  cause this crash — the bundle root is empty wherever the app sits — and it
  belongs with the install work committed this morning.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `previews`: a 3D model opens in an installed release, on a machine that did
  not build it, and a viewer that cannot find its shaders is a pane that says
  so rather than a process that ends.

## Impact

- **gostl** (`~/dev/oss/gostl`, the maintainer's package): `MetalRenderer.
  loadShaderLibrary`, the icon lookup in `GoSTLApp.swift`, and `MetalView`'s
  handling of a renderer that fails to initialise. A release, `0.23.6`, which
  only the maintainer publishes — the house rule against pushing stands.
- **Abydos**: `Package.swift` (`exact: "0.23.6"`), `ModelContainerView` or
  where the viewer is made (the pre-check), `Scripts/bundle.sh` (the note about
  the build path becomes the reason for the driven check), release notes.
- **Driving**: a `--metal-shot` run on a scratch copy with
  `.build/<arch>/release/GoSTL_GoSTL.bundle` moved aside for its duration and
  put back after.
