## 1. The bytes and the arithmetic, in AbydosKit

- [ ] 1.1 `GitRepository.runData` beside `run`, returning stdout as `Data`; `GitBlob.read(_ rev: String, path: String, in root:) -> Data?`.
- [ ] 1.2 `PictureDiff`: two RGBA bitmaps in, regions out — the threshold, the 16-pixel cells, the connected components, the size bound, the reasons; with tests for the scenarios in the spec.
- [ ] 1.3 `Settings.pictureDiffMode`, beside `diffIsSideBySide`.

## 2. The view

- [ ] 2.1 `PictureDiffView`: two images, labels, the fitting scale, the checkerboard; side by side.
- [ ] 2.2 The slider: the divider in picture pixels, drawn at scale, dragged, kept through a resize.
- [ ] 2.3 Changes: the regions outlined in the modified colour, the rest dimmed, the count in the caption; the reason when there are none to draw.
- [ ] 2.4 The `DrawnChoice` above, reading and writing the setting; unavailable modes said, for one-sided and uncomparable pictures.

## 3. The three hosts

- [ ] 3.1 The commit page: `HEAD:`/index against index/working file by staged-ness; the view swapped for the diff view when `FilePreview.kind` says `.image`, and back.
- [ ] 3.2 The log page: parent against commit, renames followed as the text diff follows them.
- [ ] 3.3 The pull-request page: base against head when both are local; the side that is not says so.

## 4. Proving it

- [ ] 4.1 The diff report says `picture` with the mode, the two sizes and the region count; a `picture-mode:<n>` step switches.
- [ ] 4.2 Driven on a scratch repository with a picture changed in two places: the report in each mode, and a capture of each.
- [ ] 4.3 Driven: an added picture shows one side and the switch offers one mode.

## 5. Finishing

- [ ] 5.1 Say it in the release notes.
- [ ] 5.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `picture-diffs` spec in this
change is what it makes true.
