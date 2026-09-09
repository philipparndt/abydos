## 1. Build

- [x] 1.1 `ARCHS` read in `bundle.sh`: one native build per entry with a single `--arch`, and the four executables joined with `lipo`. One build with two flags was tried first and needs the Metal toolchain; see the design.
- [x] 1.2 `make build` passes `ARCHS` through; `make release` sets `ARCHS="arm64 x86_64"`.
- [x] 1.3 A universal build skips the UUID pin and says so.
- [x] 1.4 The bundle prints `architectures: …` before `Done`.

## 2. Proving it

- [x] 2.1 `make build ARCHS="arm64 x86_64" PIN_UUID=0` under a throwaway identifier: `lipo -archs` reports `x86_64 arm64` for the app, the hook, the bench and the backlog binaries, and the bundle prints the same; `codesign --verify --strict` passes.
- [x] 2.2 The x86_64 slice opens a project under Rosetta: under `arch -x86_64`, and again as a thin x86_64 binary cut out with `lipo -thin`, the app opened the project, zoomed on request and captured a screenshot, exit 0.
- [x] 2.3 `vtool -show-build` on the universal app reports `minos 14.0`, `sdk 14.0` for both slices.
- [x] 2.4 A plain `make build` is still native, and still pins: `architectures: arm64`, and the UUID line printed.

## 3. Finishing

- [x] 3.1 Nothing in Swift changed, so `make test` and `make warnings` stand as run for `a-double-click-zooms-once` the same afternoon; `bash -n Scripts/bundle.sh` passes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue, and no
`openspec/specs` capability says which processors the download is for.
