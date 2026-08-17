# 539. A file from a toolchain rather than a declared dependency has no home in the tree

> and also when navigating to go core dependencies, this is not revealed in the
> dependencies section. I think we are missing an important part for the
> dependencies node to actually work

The screenshot is the case exactly: `time.go` open in a tab marked `↗`, showing
`runtimeNano()` and `unixToInternal` — Go's **standard library**, from the
toolchain's own `src/time`. Navigation worked and the file opened. Nothing in the
tree points at it, and the `Dependencies` node cannot: `go-service` under it
reads `no dependencies`, which is the true answer about its `go.mod`.

**So this is a gap, not a bug.** Every reader behind that node answers the
question "what has this project declared, and what did that resolve to" — a
`Package.resolved`, a `go.mod`'s `require`s, a `Cargo.lock`. A toolchain's own
sources are declared by nobody. They arrive with the compiler, and the only thing
that knows where they are is the language server that just sent you there.

## What has no home today

Worth listing, because the answer should cover the class rather than Go:

- **Go's standard library**, in `GOROOT/src`. The reported case.
- **The Swift standard library and the SDK's own modules**, which
  go-to-definition reaches constantly — every `String`, every `Array`.
- **C and C++ system headers**, from the SDK the clangd invocation names.
- **A Java JDK's own classes**, where jdtls hands back a path inside the
  platform's `src.zip` or a decompiled stub.

0508 gave a file outside the project *a place*; what it gave it was a place under
the thing that declared it. These have no declarer, so they fall out of that
model rather than being mishandled by it.

## Worth deciding

- **Whether they belong under `Dependencies` at all.** A heading that means "what
  this project depends on" is arguably the wrong parent for a compiler's own
  sources — IntelliJ, whose *External Libraries* this node is modelled on, does
  put the JDK there, so there is precedent either way. A sibling root, or a
  section within, are both defensible. Decide and say why.
- **Where the location comes from, and it must not be guessed.** `GOROOT` is
  `go env GOROOT`, and the project's own rule is that nothing runs a build tool
  to answer the dependencies section — so this needs either an exception with a
  written reason, or the same "the tool's environment variable, then the default
  under the home directory" shape `goModuleCache()` and `cargoHome()` already
  use. **The honest alternative: take it from the answer the language server
  already gave.** The file's path is in hand at reveal time; the toolchain root
  can be derived from it rather than asked for.
- **Whether the node is built lazily.** A JDK's `src.zip` and an SDK's headers
  are tens of thousands of files. The package rows under this node are
  `FileNode`s rooted at a checkout and listed lazily, which is the mechanism that
  makes this affordable — but a row per stdlib package for Go is a different
  shape from one row per resolved dependency.
- **What it is called when there is no version.** A dependency row carries a
  version and an origin. A toolchain has a version (`go1.24.13`, a Swift
  toolchain identifier) but no origin in the sense the rows mean, so
  `DependencyNode.subtitle` needs an answer that is not a blank.
- **Whether a file with no home should say so.** Independent of this node, and
  cheaper: a tab marked `↗` that the tree cannot reveal could say why when
  somebody asks to reveal it, rather than doing nothing. That is the failure the
  report actually describes.

## Steps

- [ ] Following a symbol into a toolchain's own sources reveals it somewhere in
      the tree, with its siblings, for Go at least
- [ ] The decision about which parent it hangs under is written down, with the
      IntelliJ precedent addressed rather than assumed
- [ ] Where the toolchain root comes from is written down, and does not break the
      rule that nothing runs a build tool to fill this section — or states its
      exception plainly
- [ ] Opening one is affordable on a large SDK: nothing walks it eagerly
- [ ] The other three cases — Swift, C headers, a JDK — are either covered or
      named here as not covered, with the reason
- [ ] A file the tree genuinely cannot place says so when reveal is asked for
- [ ] `make test` and `make warnings` are clean
- [ ] `spec/project-view.md` says what the project now does
- [ ] Write down here what was ruled out on the way
