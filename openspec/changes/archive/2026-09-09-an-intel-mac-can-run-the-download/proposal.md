## Why

The download runs on Apple silicon only. `Scripts/bundle.sh` runs one
`swift build` for the machine it is on, and every release has been cut on an
arm64 machine, so `Abydos-<version>.dmg` carries an arm64 binary and the cask
says nothing about architecture. Dragged to Applications on an Intel Mac, the
app refuses to open: "this application is not supported on this Mac".

Asked for on 2026-09-09, in the same sitting as `a-double-click-zooms-once`:
*"what would it mean to build a intel version? Is this any effort at all?"* —
and then to build it.

It is little effort, and that is worth saying with the evidence: there is no
`#if arch` anywhere in `Sources`; the one prebuilt library,
`Vendor/ghostty-vt.xcframework`, ships an `arm64_x86_64` slice already; the 3D
viewer's shader is GPU code; `vtool` rewrites the SDK marker of both slices of
a fat binary in one call (checked against a copy of `/bin/ls`); and `codesign`
and `notarytool` take a universal binary as they take a thin one. What was
missing was the flag.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-09.

## What Changes

- **`ARCHS` on `make build`.** `make build ARCHS="arm64 x86_64"` runs one
  native `swift build --arch <arch>` per architecture and joins the four
  executables — the app, the hook, the bench and the backlog tool — with
  `lipo`. Not one build with two `--arch` flags: that hands SwiftPM's work to
  the Xcode build system, which compiles the 3D viewer's Metal shader itself
  and needs a toolchain this machine has not got. It failed here with
  `cannot execute tool 'metal' due to missing Metal Toolchain`, the very
  failure the shader step in `bundle.sh` exists to survive.
- **`make release` builds universal.** The download is the one build whose
  machine is not known in advance. Local builds stay native: a universal build
  compiles everything twice.
- **A universal build is not UUID-pinned.** `pin-uuid.py` reads a thin Mach-O;
  rather than teach it a fat header for a case nobody drives, the bundle says
  it skipped the pin.
- **The bundle says what it is.** `architectures: arm64 x86_64` on the last
  line before `Done`, so a release that came out thin is seen at the moment it
  was built.

## Capabilities

None. This is the build, not the app: nothing under `openspec/specs` says which
processors the download runs on, and this change does not start one.

## Impact

- **Scripts/bundle.sh**, **Makefile**: the flag, the release default, the pin
  skip, the summary line.
- **Release**: `make release` takes about twice as long to compile. The DMG
  name, the cask and the notarisation are unchanged; the cask already limits
  by macOS version (`:sonoma`) and not by processor.
- **Not tested on an Intel Mac.** There is none here. The x86_64 slice was run
  under Rosetta on this machine, which proves the slice loads, links and opens
  a project; it does not prove performance or anything Rosetta smooths over.
