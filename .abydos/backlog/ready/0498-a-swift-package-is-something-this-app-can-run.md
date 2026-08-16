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

## Steps

- [ ] `RunConfiguration` finds executable targets in a `Package.swift` project
- [ ] It runs one, with the package root as the working directory
- [ ] Decide about `swift test` as a kind, and do it or write down why not
- [ ] Tests for discovery against a manifest with more than one executable
- [ ] Watched in the app: a Swift package's executables in the run list, and
      one of them actually running
- [ ] Write down here what was ruled out on the way
- [ ] `spec/run-configurations.md` says what the project now does
