## 1. The strip

- [x] 1.1 `PaneActivityView`: the two-point strip at the seam and the sweep,
      no panel and no stroke; `install(over:message:below:paneIsEmpty:)`;
      the seam re-read in `layout()`.
- [x] 1.2 The sentence centred beneath only when `paneIsEmpty`; *· still
      waiting* after five seconds on a timer the view owns and cancels in
      `finish()`.
- [x] 1.3 `count(_:of:saying:)` as the same strip filling from the left.

## 2. Every pane

- [x] 2.1 The seven callers pass their header as `below:` — changes, branches,
      history, pull-request list, estate overview — and nothing for the
      pull-request page and the tool switch; each answers `paneIsEmpty`.
- [x] 2.2 The project tree: the strip under `NavigatorHeaderView` while a
      project loads and while a reload's status sweep and dependency walk run;
      not for the watcher's reads.
- [x] 2.3 The Backlog pane: the strip under its header while `reload()` is off
      the main thread.

## 3. The previews

- [x] 3.1 `CadovaPreviewView` and `DiagramPaneView`: the spinner out of the
      notice stack, `spin(_:)` installing and finishing the strip at the top
      edge with `paneIsEmpty` from the viewer or the picture; `strip=` in the
      reports.

## 4. The tree's refresh

- [x] 4.1 `NavigatorHeaderView`: a fourth button, `arrow.clockwise`, tip
      *Re-read the project*, calling `reloadTree()` and `refreshGitStatus()`.

## 5. Proving it

- [x] 5.1 `--hold-activity`, and the `activity` report from the tree's and the
      sidebar's steps.
- [x] 5.2 Captures at 1.0 and 2.0: the pull-request list empty and with rows
      (a repository with a GitHub remote, or the trouble sentence beneath), the
      tree opening the scratch checkout, a diagram being drawn, the strip's y
      against the header's bottom in the report; recorded in the design.

## 6. Before finishing

- [x] 6.1 The release note from the design, in the notes for the next version.
- [x] 6.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.
