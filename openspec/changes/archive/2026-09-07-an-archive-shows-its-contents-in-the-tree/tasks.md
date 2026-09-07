## 1. Reading archives

- [x] 1.1 `Sources/AbydosKit/Archive/Gzip+Inflate.swift` — `Gzip.inflate`,
  moved from `PprofProfile.gunzip` with its header walk and its capacity
  floor; the profiler calls it.
- [x] 1.2 `ArchiveKind.swift` — which names are offered *Show Contents* (the
  hex editor's `ZIPFormat.knownAs` plus `zip`, `tar`, `tgz`, `tar.gz`, `gz`)
  and which first bytes decide the kind.
- [x] 1.3 `ArchiveIndex.swift` — `ArchiveEntry` (path, size, isDirectory,
  kind of member, how to read it) and `ArchiveIndex.read(url)`: a zip from
  its end-of-central-directory record and central directory, a tar by its
  headers with GNU long names and pax names applied, a tgz inflated to a
  256 MB cap, a lone gz as one entry. Keyed on size and modification time.
- [x] 1.4 `ArchiveEntry.read()` — the zip member from its local header with
  the header's own name and extra lengths, method 0 copied and method 8
  inflated through `Compression`, any other method refused with a sentence;
  a tar member as a slice; sizes checked.
- [x] 1.5 `ArchiveCache.swift` — an entry written once under
  `~/Library/Caches/abydos/archives/<key>/<path>` and its URL returned.
- [x] 1.6 `Tests/AbydosKitTests/ArchiveIndexTests.swift` — archives made in
  the test with the system's `zip`, `tar` and `gzip`: the listing of each,
  the jar's `META-INF`, a member read back byte for byte, a deflated and a
  stored member, a pax long name, the misnamed file, the cap, the key
  changing when the file is replaced.

## 2. The rows

- [x] 2.1 `Sources/AbydosKit/Project/ArchiveNode.swift` — the fourth node
  kind: the archive's own row wrapping its `FileNode`, a directory inside,
  an entry; children from the index; sorted folders first as the tree sorts.
- [x] 2.2 `ProjectNavigatorViewController+Archives.swift` — the data source's
  case, the cell with name and size, the spinner while reading, *Show
  Contents* and *Hide Contents* on archive file rows and hidden elsewhere,
  *Open*, *Open as Hex*, *Extract…* and *Copy Path* on inner rows and nothing
  that needs a file on disk. The main file gains only the dispatch.
- [x] 2.3 The shown set in `TreeFolds.opened` as `archive:<relative path>`,
  written where `folder:` keys are written and restored where they are
  restored, the archive expanded on restore.
- [x] 2.4 `ArchiveNodeTests` — the row kinds, the sort, the fold key.

## 3. Opening and extracting

- [x] 3.1 `TextDocument.isReadOnly` and the guard in `CodeView`'s insertion
  funnel — one method if there is one, each if there are several, the count
  written down — declining and beeping.
- [x] 3.2 `EditorViewController` — opening an entry from its cache URL as a
  read-only tab whose subtitle names the archive; ⌘S refused with the
  sentence that names *Extract…*; a member that cannot be read opens the
  notice with the reason.
- [x] 3.3 *Extract…* — the entry or its subtree written beside the archive,
  asking before overwriting, the result selected.

## 4. The example

- [x] 4.1 In `~/dev/abydos-examples`: `make charts` packages
  `multi-tier/deploy/chart` into `multi-tier/deploy/charts/` as well as
  linting it; the `.tgz` committed; the README's multi-tier row and the
  project's own README say what it is for. Committed there, never pushed.

## 5. Proving it

- [x] 5.1 `--tree` gains `show-contents`, `hide-contents` and `extract`; the
  `menu` report shows the items.
- [x] 5.2 Driven on 2026-09-07 over a copy of `abydos-examples/multi-tier`
  and the hex fixtures under the scratchpad:
  - *The chart:* `show-contents` on `multi-tier-0.1.0.tgz`, `down`, `right`
    opened `multi-tier/`, three `down`s reached `values.yaml`
    (`selected: multi-tier-0.1.0.tgz!/multi-tier/values.yaml`), `return`
    opened it: `tabs: … Chart.yaml~ [inside multi-tier-0.1.0.tgz, read only],
    values.yaml [inside multi-tier-0.1.0.tgz, read only]` — the provisional
    tab from arrowing past, the pinned one from Return. Its menu: `Open |
    Open as Hex | Extract… | Copy Path`. `extract` wrote `values.yaml` beside
    the `.tgz`; `archive-rows` listed `multi-tier ▾ / templates / Chart.yaml
    186 B / values.yaml 514 B`, and nothing but the extracted file appeared
    on disk. Screenshot `archive-chart.png`.
  - *A jar:* `library.jar` shown as `c / a.txt 8 B / b.txt 15 B`, and
    `hide-contents` made it a leaf again.
  - *A text file:* `notes.txt`'s menu has no *Show Contents*.
  - *The misnamed file:* `fake.zip` shows one row, *This is not an archive
    this app can read.*
  - *Read only:* `TextDocument.isReadOnly` declines `replace` in
    `TextDocumentTests`, and the tab says so; a driven keystroke and ⌘S are
    not driven, since the driver has no step that types into a tree-opened
    tab, and the guard is the one line every edit passes through.
  - *Across a project switch:* not drivable — a driven run neither restores a
    session nor writes one, by the sessions spec. The keys ride the same
    `TreeFolds` record as the folder keys, through the same getter and
    setter, and `ArchiveNodeTests` pins their shape.

## 6. Finishing

- [x] 6.1 `Scripts/file-size-allowed.txt`: the navigator raised 4611 → 4646
  by its dispatch lines alone — the data source's four arms, the menu's
  install and update, the fold keys, the Return and selection arms; every new file under a thousand lines, the largest
  `ArchiveIndex.swift`.
- [x] 6.2 `docs/release-notes-0.16.0.md` has the section.
- [x] 6.3 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [x] 6.4 Green by their exit codes on 2026-09-07: `make test` 4236 tests in
  538 suites, exit 0 with the suite's two standing known issues, load 42.2
  over 10 cores; `make warnings` exit 0, *No warnings in this repository's
  Swift*.
