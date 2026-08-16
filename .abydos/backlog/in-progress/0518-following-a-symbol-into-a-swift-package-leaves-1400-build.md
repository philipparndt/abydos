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

## What wrote them

The process list, watched while it happened, and then the compile run again by
hand until it did it on demand. Three links, and only the last one is this
program's:

**1. sourcekit-lsp prepares a second package, the one inside `.build`.** Open a
file under `<root>/.build/checkouts/<Package>` — which following a symbol, or
the project tree, will do — and sourcekit-lsp treats that checkout as a SwiftPM
package of its own, beside the project's, and prepares it. Caught in `ps`, a
child of the `sourcekit-lsp` this app started:

    swift-build --build-system native
      --package-path <root>/.build/checkouts/Cadova
      --scratch-path ~/Library/Caches/abydos/index/cadova-models-<hash>
      --disable-index-store --target Cadova --experimental-prepare-for-indexing

That is the only build on the machine whose inputs are the `.build/checkouts`
copy of Cadova — and the leaked `.d` files name exactly those 356 files as their
prerequisites. It is also why the four extensions are *those* four:
`--experimental-prepare-for-indexing` emits a module per file instead of an
object, so a prepared target is `.d`, `.dia`, `.swiftdeps` and a partial
`.swiftmodule` and no `.o`. The scratch path's own `Cadova.build` holds exactly
that set, 356 of each; `Angle-2.swiftmodule` in the project root is 28240 bytes
and so is `Angle~partial.swiftmodule` in the scratch.

**2. The two packages share one output file map, and the compile stops
recognising its own inputs.** Both builds — the project's, and the checkout's —
are given the *same* `--scratch-path`, so both write
`<scratch>/…/Cadova.build/output-file-map.json`. The map is keyed by absolute
source path. The project's build keys it by `<scratch>/checkouts/Cadova/…`; the
checkout's build keys it by `<root>/.build/checkouts/Cadova/…`. Whichever wrote
it last, a compile can find itself looking its primary inputs up in a map that
names the *other* copy — and a supplementary output with no entry in the map is
not an error. swift-driver falls back to a **temporary** path for it.

**3. A temporary that resolves relative is written where the process stands.**
That is the `-2`: swift-driver's own uniquing suffix for temporary files, and
nothing to do with `-emit-module`. `swiftc -driver-print-jobs a.swift b.swift -o
prog` names its ordinary temporaries `Alpha-1.o`, `Beta-1.o` in exactly the same
way. The frontend was handed `Angle-2.swiftmodule` with no directory in it, and
wrote it in its working directory — which it inherited from `swift-build`, which
inherited it from `sourcekit-lsp`, which this app started **in the project
root**.

So: nothing in this program compiled anything. What this program did was stand
the compiler in somebody's checkout.

### Reproduced, and counted

The fixture is a copy of `abydos-examples/cadova-models`. Steps 1 and 2 above
are what the app does on its own; the third is what makes the file land, and it
is put into that state deliberately here — the output file map rewritten to name
the other copy of Cadova, then the target's own compile command out of
`debug.yaml` run from the project root:

| | files in the project root |
| --- | --- |
| before | **0** |
| after | **1424** |

`AddingExclusive-2.d`, `AddingExclusive-2.dia`, `AddingExclusive-2.swiftdeps`,
`AddingExclusive-2.swiftmodule`, … — the same 1424 names, in the same order, as
the ones in `abydos-examples`.

The same compile, unchanged, run from `~/Library/Caches/abydos/index/<project>-<hash>`
instead: **0** in the project root, 1424 in the scratch path. That is the fix,
measured.

### What is *not* claimed

The window in link 2 — the map on disk belonging to the other package when a
compile reads it — was not caught happening on its own. Six attempts did not
produce it: the app on a cold index, the app on a warm one, the two `swift-build`
invocations by hand in each order, both at once (SwiftPM's lock on the scratch
path serialises them), `--build-system swiftbuild`, and the checkout package
built with no `--scratch-path` at all. It is a race, which fits what the report
already said — it did not happen on the runs where the definition resolved
immediately, and 20:18's leak lines up with the minute the scratch path's
`checkouts` directory was still being fetched into.

That is why the fix is where it is. Which build takes a temporary path, and why,
is the toolchain's business and may be closed there tomorrow. Where a relative
write *lands* is this program's business, and it is settled for every such write
at once.

## Ruled out

- **That anything in this app compiles the package.** It does not. The four
  extensions come from `swift-frontend`, under a `swift-build` that sourcekit-lsp
  started for itself.
- **The Cadova preview pane.** It runs `swift run <product>` in the package root
  — the right working directory, the right `.build/checkouts` sources, and the
  wrong outputs: an ordinary build writes `.o` per file and no per-file
  `.swiftmodule`, and `.build/…/Cadova.build` in the reporter's own checkout has
  356 `.o` and not one partial module.
- **`TMPDIR`.** The obvious explanation for a temporary in the wrong place, and
  it is not this. swift-driver on this machine resolves temporaries under
  `/var/folders/…/T/TemporaryDirectory.XXXXXX` with `TMPDIR` unset *and* with it
  empty; pointed at a directory that does not exist it fails with
  `couldNotFindTmpDir` rather than falling back to the working directory.
  Nothing in this app changes `TMPDIR` — the only environment variable it edits
  by name is `TMUX_TMPDIR`, for the terminal.
- **That `--scratch-path` was not being passed.** It was, on every sourcekit-lsp
  in `ps` for this project. The scratch path is not the problem; it is the only
  reason the *other* several gigabytes are not in the checkout too.
- **A second sourcekit-lsp with no arguments.** There is one running on this
  machine — Claude Code's — and its working directory is `~/dev/abydos`, not the
  examples repository.
- **The generated-interface path.** 508 found the same gesture answering with
  `…/T/sourcekit-lsp/GeneratedInterfaces/…` once the index is warm. Nothing is
  written to the project on that route.

## The fix

`LanguageServers.workingDirectory(for:root:)`, beside `arguments(for:root:)` and
answering the matching question: the Swift server is *started* in the directory
its index already lives in, and every other server is started in its project,
which is what has always been right for them. Nothing about finding the project
depends on the working directory — `rootUri` and `workspaceFolders` are absolute
file URLs in the initialize request, `--scratch-path` is absolute, and every
`--package-path` the server passes on is absolute too.

Only on the installed route, and for the same reason `prepare` is: the directory
a container runtime is started in is not the directory the server runs in, and a
cache path from this machine would say nothing about either. A scratch directory
that could not be created leaves the project as the answer, because a `Process`
whose working directory does not exist refuses to run at all.

## The 1424 files already in `abydos-examples`

Left alone. They are in somebody else's repository, they are the evidence this
item was written from, and deleting them is not this item's call. Nothing in
`abydos-examples` tracks any of them, so when the owner wants them gone:

    cd ~/dev/abydos-examples/cadova-models
    ls -A | grep -E -- '-[0-9]+\.(d|dia|swiftdeps|swiftmodule)$' \
      | while read -r f; do rm -f "./$f"; done

`git status` in that repository is the check: three files, and nothing else.

## Steps

- [x] Reproduce it deliberately, on a project with no index yet
- [x] Watch the process list and name the invocation that writes them
- [ ] Give that invocation an output directory under the index scratch path,
      where everything else about the index already lives

  Not done, and not going to be: the invocation is sourcekit-lsp's own
  `swift-build`, started by the server rather than by this app, and there is no
  argument on it to give. What this app owns is where the server stands, which
  is the step below.
- [x] Say where the `-2` in the names comes from, and what writes each extension
- [x] Start the Swift server in its index scratch path, not in the project
- [ ] Clean up the 1424 files already in `abydos-examples/cadova-models`

  Not done deliberately. Somebody else's repository; the command is above for
  whoever owns it.
- [x] A test, if the invocation can be asked about without a language server
- [x] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says where the Swift indexer writes

## Estimate

2026-08-16 22:40 — done, bar the suite
