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

## What was decided

**The root comes from the answer, not from a question.** `ToolchainSources`
recognises a toolchain in a path that has *already been handed to us* — gopls
answered `textDocument/definition` with `…/go/libexec/src/time/time.go`, and
`$GOROOT` is the part of that above `src`, confirmed by a `VERSION` file
beginning `go` sitting in it. No `go env`, so the no-build-tool rule is intact;
and no `$GOROOT`-then-`~/go` either, so this is *stricter* than the shape
`goModuleCache()` and `cargoHome()` use rather than an exception to it. Those
two have to guess because they run when a project opens and have to go looking.
This does not: the file's path is in hand, and a machine with three Go
installations gets the one the file came from rather than the one on the PATH.

The price is that a toolchain has no row until somebody has been into it. That
is written down as a feature and meant as one — a row for a toolchain nobody
has visited would be a guess about which compiler the project builds with, and
it would be wrong on the first machine with two.

**Under `Dependencies`, after the packages.** IntelliJ's *External Libraries*
holds the JDK, so the precedent points this way, but the precedent is not the
argument. The argument is that `DependencyTree.locate` is the one thing allowed
to win over the ordinary tree for a file, and a sibling root would need its own
copy of it and a second rule about which root claims a file; that a root of its
own would have to exist before anything was found to put in it, which is the
permanent empty row 508 was filed to prevent; and that the section already
claims to be what the project is made *from*. The misreading it invites — that
the project declared this — is denied on the row itself: `go1.26.6 · toolchain`,
and a tooltip saying no manifest names it.

**The subtitle is never the version alone.** `go1.26.6` on its own reads as a
package whose origin this program failed to read, which is a worse claim than
saying nothing. `Toolchain.provenance` is the word that stands where a package's
origin stands — `toolchain`, `SDK` — and it is what an unversioned toolchain
falls back to.

**Lazy by being the same shape as a package row.** The row's children are a
`FileNode` rooted at a directory, which lists when it is expanded and not
before. Go's row is rooted at `$GOROOT/src` so its children are the standard
library's packages rather than `api`, `bin`, `lib`, `misc`, `pkg` and `test`;
an SDK's is rooted at the `.sdk` itself, because headers, frameworks and Swift
modules are under three different subtrees of it.

**Covered: Go and Apple's SDKs.** The SDK case is the C and C++ system headers
of the item's third bullet — clangd answers with real paths inside the `.sdk`
it was given, and `SDKSettings.json` names it and its version.

**Not covered: a JDK.** jdtls answers with `jdt://contents/…` URIs, and where
it does name a file it is an entry inside the platform's `src.zip`. Nothing
here reads an archive, and a row rooted at a zip would be a folder holding one
binary file. The nearest thing that works is what kmp-lsp already does — unpack
into `~/.cache/kmp-lsp` — and a row rooted at a language server's scratch cache
would be a row about the server rather than about the JDK.

**Not covered: the Swift standard library**, and for a different reason. What
sourcekit-lsp hands back for `String` is not a file in the toolchain: it is a
generated interface, either behind a URI scheme this program cannot open at all
or written into a scratch directory for the occasion. There are no siblings to
show and nothing that will still be there tomorrow to root a row at. Where the
Swift sources genuinely live inside an `.sdk`, the SDK row already places them,
which is why the SDK recogniser was worth having beyond the C case.

### Ruled out on the way

- **`go env GOROOT`.** It is running a build tool, which the section's own rule
  forbids, and it would cost a process launch to answer a question the path
  already answers.
- **`$GOROOT`, then `/usr/local/go`, then Homebrew's `libexec`** — the
  `goModuleCache()` shape. Rejected because it is a guess where no guess is
  needed: it would name a toolchain on a machine that has one, and the *wrong*
  toolchain on a machine that has two.
- **Reading toolchains when the project opens.** Nothing declares them, so
  there is no list to read; it would mean the guess above, and a row for a
  compiler nobody has been near.
- **A third root beside `Dependencies`.** Two roots that can both claim a file
  is two rules about reveal, and it would be an empty row on every project.
- **A `Toolchains` group row.** Over-nesting for what is usually one row, and
  it would put two clicks between somebody and the file they were just sent to.
- **Reshaping the section into groups when a toolchain appears.** It is tidier
  — the section's heading names a build system, and the toolchain row is not of
  that kind — but the rows would change identity, so whatever somebody had open
  would fold up underneath them in the middle of the navigation that found the
  toolchain. The mixed level is the lesser fault and is written down in
  `DependencyTree`.
- **`fileExists` for `VERSION` and `SDKSettings.json`.** A Mac formats a disk
  case-insensitively, so it answers yes for a `version` file; the names are
  read and matched exactly, which is the rule `FilePath.entryNames` exists for.
- **A toast on every reveal that lands nowhere.** Switching tabs reveals, a
  hundred times an hour. Only the asked-for gesture — the locate button, its
  menu item — says anything.

### Seen working, not only tested

Driven through `--tree` against a scratch Go module (`go.mod` with no
`require`), never a real checkout:

- `reveal:$GOROOT/src/time/time.go` — the section went from `Dependencies — Go
  modules | no dependencies` to that plus `Go standard library — go1.26.6 ·
  toolchain`, and `rows` shows `time.go` selected with all of `time`'s files
  beside it and the standard library's packages above it.
- The same file opened as a tab, which is what following a symbol does:
  selected on arrival, and `locate` says nothing because there is nothing
  wrong.
- `MacOSX.sdk/usr/include/stdio.h` opened as a tab: `macOS SDK — 27.0 · SDK`,
  `stdio.h` selected.
- A loose file outside the project, `locate`: one toast, `notes.md is not in
  the tree — it is outside the project, and no package or toolchain in
  Dependencies holds it.`

## Steps

- [x] Following a symbol into a toolchain's own sources reveals it somewhere in
      the tree, with its siblings, for Go at least
- [x] The decision about which parent it hangs under is written down, with the
      IntelliJ precedent addressed rather than assumed
- [x] Where the toolchain root comes from is written down, and does not break the
      rule that nothing runs a build tool to fill this section — or states its
      exception plainly
- [x] Opening one is affordable on a large SDK: nothing walks it eagerly
- [x] The other three cases — Swift, C headers, a JDK — are either covered or
      named here as not covered, with the reason
- [x] A file the tree genuinely cannot place says so when reveal is asked for
- [x] `make test` and `make warnings` are clean
- [x] `spec/project-view.md` says what the project now does
- [x] Write down here what was ruled out on the way
