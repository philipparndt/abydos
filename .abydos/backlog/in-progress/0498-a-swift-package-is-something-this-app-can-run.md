# 498. A Swift package is something this app can run

`RunConfiguration` finds what a project can run without being configured, and
it knows ten kinds: IntelliJ and VS Code launch files, `make`, a Go module,
Maven, Gradle, a Java main, an Xcode scheme, Bazel and Conan. **Not SwiftPM.**
`mainPackages` scans for Go's `package main`; nothing looks at `Package.swift`.

The joke is that this project is a Swift package and is run through `make`,
which is why nobody has missed it.

It comes up now because 0499 needs it: a Cadova model is an executable target
in a Swift package, and seeing the geometry means running that target. But it
stands on its own — a Swift package with executables is a thing somebody opens
here, and the run list should have them in it.

## What was measured

From the spike for 0499, on this machine, Swift 6.4, a package depending on
Cadova 0.9.1 and therefore on Manifold's C++:

    swift package resolve      22s   (7 packages, once)
    swift build (cold)         46s   (719 units)
    swift run (warm, no edit)  ~1s
    edit one constant, run     ~2-4s

So a Swift run is not the expensive thing it was assumed to be, and does not
need a design that hides it behind a progress sheet.

## Worth deciding

- **What the list shows.** `swift package dump-package` gives the executable
  targets as JSON, which is the honest source and costs a subprocess. Parsing
  `Package.swift` by hand is what `mainPackages` does for Go and would be
  guessing here, because a manifest is a program.
- **Whether a package's tests are a run kind too.** `swift test` is the obvious
  neighbour and the same discovery. Probably yes, but it is a decision.
- **Where the working directory is.** Cadova writes its output beside the
  package, so `swift run` in the package root is what a person would type. Say
  it out loud, because 0499 depends on where the file lands.

## What was decided

### 1. The manifest is read, not run — and the item's framing above was wrong

The paragraph under "Worth deciding" calls `swift package dump-package` "the
honest source" and parsing "guessing". Having measured it, that is the wrong way
round for this job, and the file being changed had already said so three times:

- `XcodeProject.swift:3` reads `xcshareddata/xcschemes` off disk rather than
  running `xcodebuild -list`, because the subprocess takes seconds and this is
  asked on every scan — and adds that the on-disk answer is also *better*.
- `RunConfiguration.swift:541` rules out `bazel query` in nearly the same words.
- `ConanProject.swift:11` refuses to execute `conanfile.py` and reads the `name =`
  line instead: "Running it to ask would mean running somebody's build script to
  populate a menu."

`Package.swift` is a program in exactly the way `conanfile.py` is, and
`dump-package` compiles and runs it. Four things measured on this machine,
Swift 6.4 via `xcrun`:

| | |
|---|---|
| `dump-package`, this repository, warm | **0.92 s** |
| `dump-package`, this repository, `--manifest-cache none` | **0.74 s** |
| `dump-package`, cadova spike, no `.build`, dependency unresolved | **0.76 s** |
| reading `Package.swift` and parsing it | under a millisecond |

Discovery is synchronous — `discover(in:)` returns `[RunConfiguration]`, there is
no async path to hide a slow call in — and it is called once per directory of a
tree three deep, and again on every write that could change the answer. A
monorepo with ten packages would pay six to nine seconds of subprocess per
rescan, and a checkout produces several rescans.

Two things the timings do not show and which mattered more:

- **`dump-package` writes a `.build/` directory into the project**, measured on a
  copy of the spike that had none. Merely *looking* at what a project can run
  would leave a build directory behind in it.
- **It answers with whichever `swift` is first on the PATH.** On this machine
  that is swiftly's, and against the very package 0499 needs it answers
  `error: 'cold-spike': package is using Swift tools version 6.3.0 but the
  installed version is 6.1.2` and lists nothing at all. The Makefile pins
  `xcrun swift` for this exact reason and says so at length; an app cannot pin
  anything, because it does not get to choose the user's toolchain. A run list
  that goes empty because somebody installed a version manager is worse than one
  read off the text.

What reading the text cannot see is an executable whose name is not a string
literal — a manifest that computes its target list. This repository's own
manifest does that, for the five vendored grammars, and they are library targets;
the four executable products are all literals. The failure mode is a missing
entry rather than a wrong one, which is the right way round.

Ruled out along the way: `swift package describe --type json` (same subprocess,
same manifest compile, no cheaper); using `xcrun swift` from the app to dodge the
PATH problem (`xcrun` needs a selected Xcode, which a machine with only the
command-line tools does not have, so it trades one blank list for another); and
running `dump-package` in the background and folding the answer in later, which
would need `discover(in:)` to become async and every caller with it, for a list
that would still be a subprocess per package per scan.

### 2. `swift test` is a kind, and it costs nothing to have made it one

Yes. It is the same file read the same way, and the objection that would have
stopped it does not apply. `isTest(_:)` matches `arguments.contains("test")`, so
a `swift test` configuration is a test run the moment it exists — which is what
the rule in that function's comment demands: "Tests are run constantly and from
anywhere in a file, so they must never become saved configurations." That rule
was written against *per-test-function* entries, hundreds of them; `swift test`
is one entry for a whole package, offered and never saved, and it needed no code
of its own to be classified. There is a test asserting exactly that, because it
is the whole reason adding the kind was safe.

Offered only when the manifest declares a `.testTarget`. A `swift test` on a
package with no tests is a menu entry that builds and then reports nothing, and
a run list that offers work with no result in it is how a list stops being read.

### 3. The working directory is the package root, and 0499 should rely on it

The directory holding `Package.swift`. It is where `swift run` has to be invoked
from to find the package at all, it is what somebody typing the command would be
standing in, and it is the house default besides — every per-directory finder in
`RunConfigurationDiscovery` passes the directory it searched, and only Bazel
(the workspace root, where labels resolve) and Gradle (the wrapper's directory)
differ, each because its own tool insists.

Said out loud in the spec as a requirement of its own, and asserted by
`itRunsInThePackageRoot`, because 0499 needs it to be a promise rather than an
accident: Cadova writes its `.3mf` beside the package, so the working directory
is what decides where the file 0499 has to find will be.

## What was watched

`--run-config <name>` is new: `--run-configs` says what the list holds, and this
says what one of them *does*, which is the question that catches a configuration
that looks right and does not run.

This repository's own manifest, copied beside its own Makefile so the driver run
could not write into the worktree — the joke the item was filed on, resolved:

    Make: build → make build
    … thirty of them …
    Swift Package: swift run Abydos → swift run Abydos
    Swift Package: swift run abydos-backlog → swift run abydos-backlog
    Swift Package: swift run abydos-hook → swift run abydos-hook
    Swift Package: swift run firebench → swift run firebench
    Swift Package: swift test → swift test

A two-executable package, started from the app:

    RUNCONFIG: starting swift run beta
    RUNCONFIG: after 8s: Building for debugging... ⏎ [1 / 1] ⏎
      Build complete! (0.28 sec) ⏎ [process exited with status 0] ⏎ beta ran

And 0499's own spike, which is the run that matters:

    RUNCONFIG: starting swift run spike
    RUNCONFIG: after 8s: [1 / 45] Cadova ⏎ Build complete! (1.68 sec) ⏎
      [INFO] Generating "hexholder"... ⏎
      [INFO] Wrote model to …/cadova-spike/hexholder.3mf ⏎
      [process exited with status 0]

`hexholder.3mf` was deleted before the run and was there afterwards, beside the
package — which is the working-directory decision, observed rather than argued.

The package with a network dependency and no `.build` at all lists exactly the
same `swift run spike`, and discovery left nothing behind in it. Reading the
manifest does not care whether resolution has happened, which `dump-package`
would have.

## Steps

- [x] Measure both ways of enumerating, and decide between them in writing
- [x] `RunConfiguration` finds executable targets in a `Package.swift` project
- [x] It runs one, with the package root as the working directory
- [x] Decide about `swift test` as a kind, and do it or write down why not
- [x] `Package.swift` in `definingFileNames`, so a package written after the
      project was opened gets its entries without reopening
- [x] Tests for discovery against a manifest with more than one executable
- [x] A driver that starts one configuration by name, so a run can be watched
- [x] Watched in the app: a Swift package's executables in the run list, and
      one of them actually running
- [ ] Write down here what was ruled out on the way
- [ ] `spec/run-configurations.md` says what the project now does

## Estimate

2026-08-16 11:55 — about two hours left
