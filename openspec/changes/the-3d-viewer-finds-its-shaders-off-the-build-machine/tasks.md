## 1. GoSTL, in `~/dev/oss/gostl`

- [ ] 1.1 Pull the clone up to `0.23.5`, the version Abydos pins.
- [ ] 1.2 `GoSTLResources.bundle`: the `ModuleResources` search — the main
      bundle's `Resources`, its root, the bundle the anchor class was loaded
      from, one level up from it, the `Resources` of the enclosing `.app` —
      then `Bundle.module` last; a test that names the order and that a
      missing bundle answers `nil`.
- [ ] 1.3 `MetalRenderer.loadShaderLibrary` and the icon lookup in
      `GoSTLApp.swift` read through it; the loader throws
      `shaderLoadingFailed` when nothing is found.
- [ ] 1.4 `MetalView`: a renderer that fails to initialise makes no renderer,
      draws nothing and reports through the existing error path; no
      `fatalError`.
- [ ] 1.5 Committed in the clone with the crash named in the message. **Tagging
      `0.23.6` and pushing are the maintainer's**; nothing here pushes.

## 2. Abydos

- [ ] 2.1 `Package.swift`: `exact: "0.23.6"` once the tag exists;
      `Package.resolved` follows.
- [ ] 2.2 Before `ModelContainerView` hosts a viewer, `ModuleResources.locate(
      "GoSTL_GoSTL", in: searchDirectories)`; `nil` shows *the 3D viewer's
      resources are missing from this build* where a render error goes and
      makes no viewer.
- [ ] 2.3 `Scripts/bundle.sh`: the note about the build path says the path is
      the builder's and points at the driven check below.

## 3. Proving it

- [ ] 3.1 A driven run on a scratch copy, built as `de.rnd7.abydos.shaders`
      with an unpinned UUID: `.build/<arch>/release/GoSTL_GoSTL.bundle` moved
      aside under a `trap` that puts it back, an `.stl` opened, `--metal-shot`
      taken; the shot shows the model. Run once before the pin bump to see it
      die where the report died.
- [ ] 3.2 The same with the app's `Contents/Resources/GoSTL_GoSTL.bundle` moved
      aside as well: the pane shows nothing and the message, the process ends
      by itself. Both recorded in the design under a dated heading.

## 4. Before finishing

- [ ] 4.1 One `##` in the next version's release notes, in the shape of 0.20.6:
      a model opens in an installed release.
- [ ] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate the-3d-viewer-finds-its-shaders-off-the-build-machine`.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `previews` is what this change
amends.
