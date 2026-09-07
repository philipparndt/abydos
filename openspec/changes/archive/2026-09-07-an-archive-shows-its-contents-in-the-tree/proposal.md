## Why

**An archive in the tree is a leaf, and the only way to see what is in it is
to unpack it beside itself.** A downloaded Helm chart is a `.tgz`; what
somebody wants from it is one look at `values.yaml` — the defaults they are
about to override — and nothing else. Today that costs a terminal, a `tar
xzf`, a `chart/` directory that git then wants to know about, and a delete
afterwards. The same is true of a `.jar` somebody is checking a resource
in, a `.whl`, a `.zip` a colleague sent. The tree draws every one of them
with `archivebox.fill` and knows nothing else about them; the Quick Look
button was even taken off archives because the system shows a zip as a large
icon with its name under it, which is an offer of nothing.

The pieces are in the house already. The hex editor's `ZIPFormat` walks a
zip's local headers and central directory, `TarFormat` walks tar's blocks,
`GzipFormat` its header, and the profiler's `PprofProfile.gunzip` inflates a
gzip stream through Apple's `Compression`. The tree already has rows that are
not files — `DependencyNode`, `SessionNode` — and a `DependencyNode` package
row is "a directory whose children are ordinary rows", which is the shape an
archive row wants.

Asked for on 2026-09-07: "compressed files shall have a context menu entry
'show contents', when using this, it is possible to expand them in the project
view and directly check the contents. This is especially useful for downloaded
helm charts. The user never wants to extract them, but check the default
values for example. Create an example in the examples project for this."

No originating backlog item: asked for directly, and the backlog is closed.

## What Changes

- **An archive row offers *Show Contents***, on its context menu, for a
  `.zip` and what is a zip under another name (`.jar`, `.war`, `.whl`,
  `.nupkg`, `.3mf`, `.docx` and the rest the hex editor already names), a
  `.tar`, a `.tgz` or `.tar.gz`, and a lone `.gz`. Chosen, the row grows a
  disclosure and opens like a folder: directories inside it are folders,
  entries are files, each with its size in the grey half. *Hide Contents*
  closes it again. Nothing is written to disk to show it.
- **An entry opens in the editor, read only,** with the tab saying which
  archive it is inside. Syntax, search in the file, the structure pane and
  the hex editor all work on it as on any file; ⌘S says the file is inside an
  archive and names the way out.
- **The way out is *Extract…* on an entry row**, which writes that one entry
  beside the archive and selects it. Whole-archive extraction is not offered:
  the terminal does that in one line, and the point of this change is not
  needing to.
- **Which archives are shown is remembered** with the tree's folds in the
  session, so a chart opened up before lunch is still open after it, and an
  archive nobody asked about stays a leaf.
- **A changed archive is read again**: the index is keyed on the file's size
  and modification time, and a `helm pull` that replaces the `.tgz` under an
  open row shows the new contents on the next expand.
- **An example in `abydos-examples`**: `multi-tier/deploy/charts/` gains the
  project's own chart packaged by `helm package`, and the README says what to
  do with it — show its contents, read `values.yaml`, never extract it.
- **Not proposed:** `.7z`, `.rar`, `.xz` and `.bz2`, which need decoders the
  platform does not ship; editing inside an archive and writing it back;
  project-wide search into archives; nested archives (a jar inside a war
  shows as a file that can itself be opened as hex).

## Capabilities

### New Capabilities

- `archive-contents`: what the tree does with an archive somebody asks to see
  into — which kinds, how the rows read, how an entry opens and why it is
  read only, the one-entry extract, what is remembered, and what a changed or
  broken archive does.

### Modified Capabilities

<!-- None. `project-view` says nothing about archives; `tree-behaviour`'s
requirements — a tree takes the keyboard, a selection survives a reload, the
app's selection colour — hold for archive rows because they are rows of the
same outline, and are not changed. `sessions`'s "a tree comes back folded as
it was left" is the record the shown archives ride in, unchanged in shape. -->

## Impact

- `Sources/AbydosKit/Archive/` — new: `ArchiveIndex` (the entry tree read
  from a zip's central directory, a tar's headers, or an inflated tgz),
  `ArchiveEntry` with `read()` (a stored or deflated zip member through
  `Compression`, a tar slice), `ArchiveKind` (which names are which), and the
  cache under `~/Library/Caches/abydos/archives/` that an opened entry is
  written to. `PprofProfile.gunzip` moves to `Gzip.inflate` beside the
  `Gzip.compress` that is already there.
- `Sources/AbydosKit/Project/ArchiveNode.swift` — the tree row, a sibling of
  `DependencyNode` and `SessionNode`.
- `Sources/AbydosApp/Navigator/ProjectNavigatorViewController.swift` — the
  menu items, the node kind in the data source, the open and the extract. The
  file is at its recorded length; what goes in it is the wiring and the rest
  goes in `ProjectNavigatorViewController+Archives.swift`.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — a tab that is inside
  an archive: read only, named, and refusing ⌘S with a sentence.
- `Sources/AbydosKit/Text/TextDocument.swift` and `CodeView.swift` — an
  `isReadOnly` the insertion path honours, which neither has today.
- `~/dev/abydos-examples/multi-tier/deploy/charts/multi-tier-0.1.0.tgz`, its
  Makefile's `charts` goal and README — a commit in that repository.
- Tests: `ArchiveIndexTests` over archives made in the test with `zip`,
  `tar` and `gzip` from the system, and `ArchiveNodeTests` for the rows.
- No new dependency: `Compression` is the platform's and already imported.
