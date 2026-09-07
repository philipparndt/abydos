## 1. Reading archives

- [ ] 1.1 `Sources/AbydosKit/Archive/Gzip+Inflate.swift` — `Gzip.inflate`,
  moved from `PprofProfile.gunzip` with its header walk and its capacity
  floor; the profiler calls it.
- [ ] 1.2 `ArchiveKind.swift` — which names are offered *Show Contents* (the
  hex editor's `ZIPFormat.knownAs` plus `zip`, `tar`, `tgz`, `tar.gz`, `gz`)
  and which first bytes decide the kind.
- [ ] 1.3 `ArchiveIndex.swift` — `ArchiveEntry` (path, size, isDirectory,
  kind of member, how to read it) and `ArchiveIndex.read(url)`: a zip from
  its end-of-central-directory record and central directory, a tar by its
  headers with GNU long names and pax names applied, a tgz inflated to a
  256 MB cap, a lone gz as one entry. Keyed on size and modification time.
- [ ] 1.4 `ArchiveEntry.read()` — the zip member from its local header with
  the header's own name and extra lengths, method 0 copied and method 8
  inflated through `Compression`, any other method refused with a sentence;
  a tar member as a slice; sizes checked.
- [ ] 1.5 `ArchiveCache.swift` — an entry written once under
  `~/Library/Caches/abydos/archives/<key>/<path>` and its URL returned.
- [ ] 1.6 `Tests/AbydosKitTests/ArchiveIndexTests.swift` — archives made in
  the test with the system's `zip`, `tar` and `gzip`: the listing of each,
  the jar's `META-INF`, a member read back byte for byte, a deflated and a
  stored member, a pax long name, the misnamed file, the cap, the key
  changing when the file is replaced.

## 2. The rows

- [ ] 2.1 `Sources/AbydosKit/Project/ArchiveNode.swift` — the fourth node
  kind: the archive's own row wrapping its `FileNode`, a directory inside,
  an entry; children from the index; sorted folders first as the tree sorts.
- [ ] 2.2 `ProjectNavigatorViewController+Archives.swift` — the data source's
  case, the cell with name and size, the spinner while reading, *Show
  Contents* and *Hide Contents* on archive file rows and hidden elsewhere,
  *Open*, *Open as Hex*, *Extract…* and *Copy Path* on inner rows and nothing
  that needs a file on disk. The main file gains only the dispatch.
- [ ] 2.3 The shown set in `TreeFolds.opened` as `archive:<relative path>`,
  written where `folder:` keys are written and restored where they are
  restored, the archive expanded on restore.
- [ ] 2.4 `ArchiveNodeTests` — the row kinds, the sort, the fold key.

## 3. Opening and extracting

- [ ] 3.1 `TextDocument.isReadOnly` and the guard in `CodeView`'s insertion
  funnel — one method if there is one, each if there are several, the count
  written down — declining and beeping.
- [ ] 3.2 `EditorViewController` — opening an entry from its cache URL as a
  read-only tab whose subtitle names the archive; ⌘S refused with the
  sentence that names *Extract…*; a member that cannot be read opens the
  notice with the reason.
- [ ] 3.3 *Extract…* — the entry or its subtree written beside the archive,
  asking before overwriting, the result selected.

## 4. The example

- [ ] 4.1 In `~/dev/abydos-examples`: `make charts` packages
  `multi-tier/deploy/chart` into `multi-tier/deploy/charts/` as well as
  linting it; the `.tgz` committed; the README's multi-tier row and the
  project's own README say what it is for. Committed there, never pushed.

## 5. Proving it

- [ ] 5.1 `--tree` gains `show-contents`, `hide-contents` and `extract`; the
  `menu` report shows the items.
- [ ] 5.2 Driven over a copy of the example under the scratchpad: the chart
  shown and `values.yaml` opened read only with the subtitle, a keystroke
  declined, ⌘S's sentence, `Extract…` writing beside the archive, a jar's
  `META-INF`, a text file's menu without the item, the misnamed file, and the
  shown chart coming back after a project switch — each with its report and
  a screenshot where one says more.

## 6. Finishing

- [ ] 6.1 `Scripts/file-size-allowed.txt` unchanged for the navigator or
  raised by the dispatch lines alone; every new file under a thousand lines.
- [ ] 6.2 Release notes section for the version after 0.15.0.
- [ ] 6.3 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [ ] 6.4 `make test` and `make warnings`, both clean by their exit codes,
  with the run's load said.
