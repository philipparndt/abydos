# 518. Following a symbol into a Swift package leaves 1400 build files in the project root

Found on 2026-08-16 while item 508 was being watched in the app. Opening
`abydos-examples/cadova-models`, waiting for sourcekit-lsp and asking for the
definition of `extruded` left **1424 untracked files in the project's own root
directory**:

    AddingExclusive-2.d
    AddingExclusive-2.dia
    AddingExclusive-2.swiftdeps
    AddingExclusive-2.swiftmodule
    Aligned-2.d
    …

Four extensions, `.d` `.dia` `.swiftdeps` `.swiftmodule`, one set per source
file of the package being indexed. `git status` in `abydos-examples` shows all
1424 as untracked, beside the three files the project actually has. Nobody
asked for a build.

## Why this is not merely untidy

`LanguageServers.indexScratchPath` exists precisely so that the Swift indexer
does *not* write into the checkout — its comment says so: "it is derived data,
it can be thrown away at any time, and a directory inside the checkout is one
more thing to add to an ignore file and one more thing to search by accident."
The server is started with `--scratch-path` pointing at
`~/Library/Caches/abydos/index/<project>-<hash>`, and that directory *is* being
used: it has its own `checkouts`, `debug`, `build.db`. Something else is
compiling with the project root as its working directory and no output path.

The cost is real: 1424 files in the tree, in every search, in `git status`, in
the file-system watcher's events, and offered to whoever next types ⇧⌘O.

## What is known, and what is not

- **Known:** it happens on `--definition` against a Swift package whose
  dependencies are checked out, on a project that had not been indexed
  recently. It did not happen on runs where the definition resolved
  immediately.
- **Known:** the artefact names are `<Type>-2.swiftmodule` and friends — the
  shape `swiftc -emit-module` leaves when it is given no output directory.
- **Not known:** which invocation it is. Candidates are sourcekit-lsp's
  background preparation, a `swift build` started to prepare the index, or the
  manifest compilation. Nobody has watched the process list while it happened.
- **Not known:** whether it predates item 508. Nothing in 508 builds anything,
  and the files appeared during a `--definition` run, so it is very unlikely to
  be new — but it has not been reproduced on an older build.

## Steps

- [ ] Reproduce it deliberately, on a project with no index yet
- [ ] Watch the process list and name the invocation that writes them
- [ ] Give that invocation an output directory under the index scratch path,
      where everything else about the index already lives
- [ ] Clean up the 1424 files already in `abydos-examples/cadova-models`
- [ ] A test, if the invocation can be asked about without a language server
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says where the Swift indexer writes
