## Context

The tree is an `NSOutlineView` over three node kinds — `FileNode` for what is
on disk, `SessionNode` for what a past session left, `DependencyNode` for the
section of packages — and the data source switches on which it was handed.
A `DependencyNode` package row is "a directory whose children are ordinary
`FileNode`s", which is why listing, sorting, git colour, the context menu and
the arrows work inside a dependency without a line written for them. An
archive cannot borrow that trick: its entries are not on disk, so they cannot
be `FileNode`s, and everything a `FileNode` gets for free — `stat`, git
status, rename, trash — is wrong for them anyway.

Reading the formats is done. `ZIPFormat` in the hex editor walks local
headers and the central directory; `TarFormat` walks 512-byte headers with
the ustar prefix; `GzipFormat` reads the header; `PprofProfile.gunzip` inflates
a gzip body through `compression_decode_buffer` with `COMPRESSION_ZLIB`, which
is raw DEFLATE — also what a zip's method 8 members are. What none of them
does is *return the bytes*: they explain, they do not extract.

Opening a file in the editor goes through `open(fileURL:)`, which makes a
`TextDocument` from a URL and a `CodeView` over it; there is no read-only
document today. The session keeps the tree's folds as `TreeFolds` — keys like
`folder:a/b` and `section:origin`, bounded to five hundred — under the name
`tree`, restored through `navigator.foldsToRestore`.

The tree file is `ProjectNavigatorViewController.swift`, at 4611 lines and
recorded at exactly that; the size rule says a file gets shorter by state
moving out of it, not by braces moving.

## Goals / Non-Goals

**Goals:**

- Seeing into a zip, a tar, a tgz or a gz from the tree without anything
  landing on disk that the person has to think about.
- An entry opening in the editor with everything a file gets — syntax,
  find, structure, hex — and nothing a file gets that would be a lie: no
  save, no rename, no git.
- The shown archives surviving a project switch and a restart.
- One entry extractable in one gesture, for the time a value really is going
  to be edited and kept.
- An example somebody can open to see the point.

**Non-Goals:**

- Formats the platform cannot inflate: `.7z`, `.rar`, `.xz`, `.bz2`. Apple's
  `Compression` has LZMA raw, not the xz container, and nothing for bzip2 or
  7z; a decoder is a dependency, and this change adds none.
- Writing into an archive. Editing `values.yaml` in place inside a `.tgz` is
  a different feature with a different failure mode.
- Search across the project reaching into archives, and the file index
  knowing archive entries. Both are wanted eventually and both multiply the
  index by the archive count; neither is this change.
- Nested archives. A jar inside a war is an entry that opens as bytes.
- Extracting the whole archive: `tar xzf` is the command, and the person who
  asked for this said they never want to.

## Decisions

### An `ArchiveNode` kind, not `FileNode`s pointing nowhere

The tree gains a fourth kind. `ArchiveNode` is one of: the archive's own row
(wrapping the `FileNode` it sits on, so the row keeps its name, icon, git
colour and the rest of the file menu), a directory inside it, or an entry.
Directories and entries carry their `ArchiveEntry` — path, size, whether it
is a directory, and enough to read it — and nothing else. The data source's
switch gains one case; the cell draws name and size; the context menu for an
inner row is *Open*, *Open as Hex*, *Extract…*, *Copy Path* and nothing
that needs a file on disk.

*Ruled out:* `FileNode`s with URLs into a cache directory. Every one would
`stat` a file that may not have been written yet, would appear in git as
untracked once it was, and would rename and trash like a file. The
dependency section can be `FileNode`s because a checkout *is* files; an
archive is not. *Ruled out:* extracting the whole archive into the cache on
*Show Contents* and treating that as a directory — a gigabyte jar would be
unpacked to show its manifest, and the person asked for the opposite.

### The index reads the directory, not the file

`ArchiveIndex.read(url)` returns the entry tree and costs what the format
costs to *list*. A zip is read from its end: the end-of-central-directory
record, then the central directory, which is one entry per member and no
data — a 200 MB jar with ten thousand classes is a few hundred kilobytes
read. A tar has no directory, so its headers are walked: one 512-byte read
per member, skipping the data by size. A `.tgz` has to be inflated to be
walked at all, and is, into memory, up to a cap of 256 MB inflated; past the
cap the row says the archive is too large to show and offers nothing else,
which is the honest answer for a file that is not a Helm chart. A lone `.gz`
is one entry named by the archive minus its suffix.

The index is built off the main thread when *Show Contents* is chosen, the
row shows a spinner meanwhile, and the result is kept on the node keyed by
the archive's size and modification time — a `helm pull` that replaces the
file under an open row is a different key, and the next expand reads again.

*Ruled out:* walking a zip from the front through local headers, as the hex
parser does — that reads every member's data past to reach the next header,
which is the whole file. The central directory exists for exactly this.

### `ArchiveEntry.read()` is the one place bytes come out

A zip member: seek to its local header, step over the name and extra fields
the header declares (the central directory's lengths may differ), then the
data — copied for method 0, inflated through `Compression` for method 8, and
refused with a sentence for any other method (bzip2 and LZMA members exist
and are rare). A tar member is a slice of the inflated or mapped bytes. Sizes
are checked against the declared uncompressed size, and a member that
inflates to something else is reported as corrupt rather than opened.

`PprofProfile.gunzip` moves to `Gzip.inflate` next to `Gzip.compress`, which
is where the second caller of a thing puts it; the profiler calls the moved
one.

### An entry opens from the cache, as a read-only document

To open an entry the editor needs a URL, because `TextDocument`, syntax,
find, the structure pane, the hex editor and the tab bar all take one. So an
opened entry is written once to
`~/Library/Caches/abydos/archives/<hash of archive path, size, mtime>/<entry
path>` and opened from there. The cache is the platform's, cleared by the
system when it likes and by nobody else; it is never inside the project, so
git never sees it, and its key changes with the archive, so a stale copy is
never opened.

The tab is marked as inside an archive: its subtitle names the archive, its
document is read only, and ⌘S says *values.yaml is inside multi-tier-0.1.0.tgz
— use Extract… on it to make a file you can change*. Read only is new:
`TextDocument` gains `isReadOnly`, and `CodeView`'s insertion path — the one
funnel every keystroke, paste and drop goes through — declines and beeps
when it is set. A buffer that can be typed into and never saved would be the
worse design; the person finds out at ⌘S that their ten minutes were in a
copy.

*Ruled out:* a document over bytes in memory with no URL. Every consumer
above would need a second path, and the file-shaped things — a language
server told about a file, the hex editor mapping one — would need inventing
twice. *Ruled out:* opening the entry into a scratch. A scratch is somebody's
and saved; this is nobody's and must not be.

### *Extract…* writes one entry beside the archive

Chosen on an entry row, it writes that file next to the archive — a
directory entry writes its subtree — under the entry's own name, asks before
overwriting, and selects what it wrote. It is the answer to "I do want to
change this", and it is per entry because that is what was asked: the default
values, not the chart.

*Ruled out:* extracting into the cache and opening that editable — the person
would be editing a file in `~/Library/Caches` without knowing it.

### The shown archives ride in the tree's folds

`TreeFolds.opened` gains keys of the form `archive:<path relative to the
project>`, written and restored exactly where `folder:` keys are. An archive
whose key is present is shown and expanded on restore; one whose key is
absent is a leaf. The record is already bounded and already per project, and
the tree-behaviour spec's promise about folds holds for these rows without a
second mechanism.

*Ruled out:* a preference. Which chart somebody is reading is about the
project they are reading it in.

### The example is the project's own chart, packaged

`abydos-examples/multi-tier/deploy/charts/multi-tier-0.1.0.tgz` is made by
`helm package deploy/chart` from the chart already there, committed as a
file (about two kilobytes), with the Makefile's `charts` goal packaging as
well as linting and the README saying what it is for: *Show Contents*, open
`values.yaml`, never extract. A chart from a public repository would have
been more like the real case and would have put somebody else's licence and
a network fetch into a repository that is meant to open offline.

### The tree file does not grow

The menu items, the data-source case and the cell go in
`ProjectNavigatorViewController+Archives.swift`; what stays in the main file
is the `switch` arms that dispatch to it. The size rule allows a file to
stay where it is recorded and no longer.

## Risks / Trade-offs

- [A zip with a data descriptor and no sizes in the local header] → the
  central directory has the sizes, and the reader uses those; the hex
  parser's "stop and say so" is not needed here.
- [A tar with GNU long names or pax headers] → the `L` and `x` entries are
  read for the name they carry and applied to the entry that follows; a name
  this does not understand is shown as the header's 100 bytes.
- [A `.tgz` that is really a `.tar` or a plain file misnamed] → the kind is
  decided from the first bytes, not the name; the name only decides whether
  *Show Contents* is offered.
- [An entry that is a symlink or a device] → listed with its kind in the
  grey half and not openable.
- [Ten thousand entries in one directory] → the outline is virtual; the
  index sorts once; the cap the hex parser has is not needed for rows.
- [The cache filling] → it is the system's cache directory, and each
  archive's entries live under one directory keyed to that archive, removed
  when the key changes; nothing else here manages it.
- [A driven run] → over a copy under the scratchpad, with the archives made
  by the run from the fixtures; the cache path is under the run's `HOME`
  when the driver sets one, and is said in the report.

## Open Questions

- **Where `CodeView`'s insertion funnel is.** Every edit should pass through
  one method; if it turns out there are three, read-only is guarded in each
  and the design records the count.
- **Whether the file index should know entries**, so ⌘P finds
  `values.yaml` inside a shown chart. Wanted, and left out here on cost; a
  follow-up once the rows exist.
