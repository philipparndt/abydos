## Context

`Scripts/bundle.sh` wraps the SwiftPM product into `build/Abydos.app`, then
compiles the 3D viewer's shader, optionally pins the executable's `LC_UUID`,
rewrites the SDK marker with `vtool` so Tahoe does not give the toolbar glass,
and signs. It builds for the host: no `--arch` is passed, and `--show-bin-path`
without one names `.build/<config>`.

## Decisions

**A flag, off by default.** `ARCHS` is read as a list and each entry is a
build of its own with a single `--arch`; empty means one build for the host,
exactly as before. A universal build compiles
every module twice, and the builds people wait on — `make run`, `make dev`, an
agent's throwaway — are the ones that must not.

*Ruled out: universal always.* Doubling every local build to make a release
correct once a month is the wrong trade, and a native build is also what
`pin-uuid.py` and `symbol-check.sh` expect.

*Ruled out, by trying it: one build with two `--arch` flags.* SwiftPM accepts
them and quietly switches to the Xcode build system for the multi-architecture
product (`.build/apple/Products/<Config>`). That build system compiles `.metal`
resources itself, so the 3D viewer's shader needs the Metal toolchain at build
time — which the native path never did, and which this machine has not
installed. The build failed with `cannot execute tool 'metal' due to missing
Metal Toolchain`. Installing the toolchain would fix it and add a requirement
to every release machine; a single `--arch` stays on the native build system
(`.build/<arch>-apple-macosx/<config>`), so two of those and a `lipo` over the
four executables builds what is wanted with nothing new installed. Grammar
bundles are queries, the same for either slice, and come from the first build.

*Ruled out: a separate Intel DMG.* Two downloads means two casks or an
architecture switch in one, two notarisations, and a user who has to know what
is in their Mac. One universal image is what every comparable editor ships.

**`make release` sets it.** The release target already sets `PIN_UUID=0` for
the same reason: a release is the build whose machine is somebody else's.

**The pin is skipped, not extended.** `pin-uuid.py` checks for `MH_MAGIC_64`
and refuses anything else, which a fat header is. The pin exists so a locally
driven build keeps its Local Network grant; a universal build is a release
build and releases pass `PIN_UUID=0` anyway. Skipping with a printed line
covers the case where somebody asks for both by hand.

**The bundle prints its architectures.** `lipo -archs` on the executable, on
the summary before `Done`. A release that came out thin — an `ARCHS` typo, a
Makefile edit — would otherwise be found by an Intel user.

## What was checked

- `vtool -set-build-version macos 14.0 14.0 -replace` on a copy of `/bin/ls`
  (x86_64 + arm64e): both slices report `sdk 14.0` afterwards.
- `xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path`
  → `.build/apple/Products/Release`, the Xcode build system; with a single
  `--arch x86_64` → `.build/x86_64-apple-macosx/release`, the native one.
- `grep -rn '#if arch' Sources` → nothing.
- `Vendor/ghostty-vt.xcframework/macos-arm64_x86_64/libghostty-vt.a` exists.
- Rosetta is installed here (`arch -x86_64 /usr/bin/true` runs), so the x86_64
  slice can be opened on this machine.

## What the Rosetta run showed

Running the Intel slice on this machine put up a system notification naming
Ghostty: "Support Ending for Intel-Based Apps — this version of Ghostty
includes a component that will not work with a future release of macOS". Not
about this app: a shell started by an Intel process is an Intel process, and
so is everything it starts, and the shell's environment on this machine reaches
into the installed Ghostty. macOS flags any Intel code it runs under Rosetta
now, which is Apple saying what the Intel build is for — Macs on macOS 26 and
earlier, since macOS 27 does not run on them and Rosetta is being wound down.
Worth having while those machines are in use; not a long-term commitment.

## What the release showed, the same evening

0.20.0 was cut with `make release-publish`, and the image carried an arm64
binary only. `make release` asks for both architectures; `publish-release.sh`
does not go through it — it runs its own `make build CONFIG=release
PIN_UUID=0` — and this change taught the flag to the target nobody uses for a
release. The design above says "`make release` asks for both" and the notes
for 0.20.0 said the download runs on an Intel Mac; both were true of a command
and false of the download. Fixed for 0.20.1 in two places: the publish script
passes `ARCHS`, and `release.sh` refuses a thin app as it refuses a pinned
UUID, so the summary line `architectures: arm64` that the bundle printed and
nobody read is a stop rather than a line.

## Open Questions

- Real Intel hardware. Rosetta proves the slice is well-formed and the app
  starts; it does not measure the terminal's drawing on an Intel GPU, which is
  the one thing in this app that would show a processor difference first.
