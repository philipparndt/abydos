## 1. The line diff

- [x] 1.1 `TextDiff` in `Sources/AbydosKit/Text/`: Myers over lines, linear
      space, over `Substring`s of the two texts, producing rows — a pair, a
      left-only, a right-only — and the changes as maximal runs of non-equal
      rows, numbered.
- [x] 1.2 The intraline pass over changed pairs: Myers over characters, taken
      only where more than half the shorter line survives, and never over a
      line longer than a few thousand characters.
- [x] 1.3 Folding: unchanged runs longer than a page collapsed to one row that
      says how many lines it hides.
- [x] 1.4 Tests, named as claims: `aLineAddedInTheMiddleIsOneChange`,
      `aCommaAddedIsMarkedAsACommaAndNotAParagraph`,
      `aLineReplacedWholesaleIsColouredWhole`,
      `twoIdenticalFilesHaveNoChanges`, `aMinifiedLineIsNotDiffedByCharacter`.
- [x] 1.5 Measure and decide the open question — patience or histogram over
      plain Myers. **Neither**, on 2,562 real revision pairs: git's own three
      algorithms describe 97% of real edits identically and differ by fractions
      of a percent on the rest, not consistently in one direction. Not on the
      corpus `Scripts/corpus.sh` clones, which are `--depth 1` and so hold one
      version of everything where a diff needs two; on revision pairs from this
      repository's history and from one Eclipse repository cloned with history.
      `TextDiffCorpusTests` is the harness and the tables are in the design.
      The measurement found two faults in our own Myers that the algorithm
      question would have hidden, both fixed: lines that can match nothing are
      now removed before the search — exact, and what git does — and the cost
      bound, which was the only guard before that, is now generous enough to
      matter. Longer than git's diff on 18 of 1,927 pairs before, on one after,
      by a single line. One gap is left and named in the design: our lone
      trivial anchors are 2–3× git's, which no algorithm change can close
      because git's three are all alike — it is the compaction post-pass, and
      it is the work worth doing next.

## 2. Sources

- [x] 2.1 `CompareSource` — `.file`, `.folder`, `.blob(repository, commit,
      path)`, `.tree(repository, commit, path)` — with what each can do: be
      read, be listed, be written to.
- [x] 2.2 A tree at a commit through `git ls-tree -r -l`: path, mode, size and
      blob in one process; a file at a commit through `GitBlob`. Never `git
      archive` into a temporary directory.
- [x] 2.3 Tests: `aTreeAtACommitIsListedInOneProcess`,
      `aBlobSourceCannotBeWrittenTo`.

## 3. The folder comparison

- [x] 3.1 `FolderComparison` in `Sources/AbydosKit/Project/`: the walk of both
      sides one directory at a time, aligned by relative path, each row
      *unknown*, *different*, *equal*, *unmatched* or *ignored*, and a folder's
      state following its children.
- [x] 3.2 Sizes decide at once; equal sizes go to a background queue that
      compares by chunks and stops at the first difference; answers cached by
      (path, size, mtime) on both sides.
- [x] 3.3 Ignore rules: either side's `.gitignore` chain — asked of `git
      check-ignore -v` in one process per side rather than of `GitIgnore`,
      which turned out to *offer* patterns and match none — and the
      navigator's built-in build-output list, with the rule that matched kept
      for the tip.
- [x] 3.4 The counts — different, equal, unmatched, ignored, comparing, listing
      — as one value the title reads.
- [x] 3.5 Staying live: one `FileSystemWatcher` per side on disk, a batch's
      stale listings re-walked and nothing else, comparisons for a re-listed
      directory cancelled and restarted, a commit side not watched.
- [x] 3.6 The marks and the apply: a list of operations, a dry summary for the
      sheet, and the apply that trashes before it overwrites or removes, in a
      scratch directory under test and never a real one.
- [x] 3.7 Tests: `twoFilesOfDifferentSizesAreDifferentWithoutBeingRead`,
      `twoFilesOfEqualSizeAreUnknownUntilCompared`,
      `aFolderIsDifferentIfAnyChildIs`, `anIgnoredRowSaysWhichRuleIgnoredIt`,
      `equalRowsAreHiddenAndCounted`, `anApplyTrashesBeforeItOverwrites`,
      `aReadOnlySideIsNeverWrittenTo`, `theCacheSkipsWhatDidNotChange`,
      `aSavedFileMovesItsRowAndReadsNothingElse`,
      `aBatchOverOneDirectoryListsItOnce`.

## 4. The page

- [x] 4.1 `CompareTab` in `Sources/AbydosApp/`: the editor tab, its title
      `A | B` and the counts line, remembered by `sessions`, and the tab that
      says a side is gone.
- [x] 4.2 The shelf: one row per source with A and B chips, drops adding to it,
      a file-against-folder chip refused with the reason in a tip. Seen in the
      demo: two letters on every card read as confusing, so the shelf became
      A over the left half, B over the right, a swap between them over the
      gutter, and the other sources a menu under either card.
- [x] 4.3 `FileCompareView`: rows from `TextDiff` drawn with the diff view's
      row drawing, `DiffHighlighter` for colour and `DiffTextRun` for selection,
      one scroll view for both halves, the path bars above each half.
- [x] 4.4 The curves in the gutter, for the changes intersecting the visible
      rect only.
- [x] 4.5 The intraline marks drawn, and the folded-run rows that open on a click.
- [x] 4.6 `Change n of m`, the two controls, the two keys, and the scroll to a
      change.
- [x] 4.7 Wrap: the editor's ⌥⌘Z switch read, a row as tall as its taller
      half by `WrapLayout`'s arithmetic, row tops prefix-summed and bisected,
      rebuilt on a width or switch change only, the current change kept in
      view across the switch.
- [x] 4.8 The history rail: `GitHistory` for the path, rows with author, hash,
      date and subject, A and B chips, the hash opening the commit page.
- [x] 4.9 `FolderCompareView`: two `NSOutlineView`s kept aligned, expanding
      together, rows drawn through `TreeRowView`, greyed for ignored, hidden
      for equal, the switch and the filter.
- [x] 4.10 The gutter with copy-to-A, copy-to-B and delete per row, the `n items
      to copy` count, the *Apply…* sheet listing operations with directions,
      and the rows it touched refreshed by the watcher rather than by a
      re-read of the page. From the demo: the bin was drawn upside down in
      the flipped gutter (`respectFlipped`), and a selected row was two pills
      with a hole between them — now one band through the gutter, both trees
      taking "has the keyboard" from either.
- [x] 4.11 A file row opening the file diff in the same tab, and the way back to
      the trees at the same row — the folder view is kept, hidden, while the
      file is open, so expansion, selection and scroll survive the way back.
- [x] 4.12 Every control through the control library, so the zoom reaches it
      (`scaled-controls`), and every action says what it does
      (`control-affordances`).

## 5. Ways in

- [x] 5.1 *Compare* in the project tree's context menu over two selected rows.
- [x] 5.2 A file or folder dropped onto an open file of the same kind, through
      `EditorDropView`.
- [x] 5.3 *Compare ▸ With…* on a file, asking with an open panel.
- [x] 5.4 `Scripts/abydos-diff`, the `compare` verb over OSC 440 inside the
      app's terminals and `open -a` elsewhere, installed by `make install-cli`.
- [x] 5.5 The `git difftool` alias in the README. The open question — how
      `--wait` learns the tab closed — is answered for now by a person:
      `abydos-diff --wait` holds until Return is pressed, and the README says
      so beside the alias. Outside the app's own terminal the request goes
      through a new `abydos://compare` URL, aimed at the shipping bundle by
      identifier so that a throwaway build never takes it; `bundle.sh` strips
      the scheme from such builds.

## 6. Driving, pictures and words

- [x] 6.1 `--compare <a> <b>` and `--compare-steps` in `LaunchOptions`, with
      the apply step refused on a driven run.
- [x] 6.2 Driven over a scratch copy under the scratchpad, by hand and
      recorded here rather than as a suite — the window layer has no test
      target, and these are the runs: `--compare A B --compare-steps
      "settle,open:Sources,mark:README.md:copy to B,report"` gives the four
      counts and the marked row; `--compare a.swift b.swift --compare-steps
      "settle,next,report"` gives `Change 2 of 2` with two folds; a page over
      a file in a repository lists its history and `history:2:A` re-diffs
      against that commit; `chip:1:A` moves the chip; a side that is gone
      comes back as a notice; `apply` is refused on a driven run. Two lessons
      from the driving are in the code: a strip that fills `dirtyRect` paints
      over the whole page on macOS 14, and a hand-framed view has to place and
      redraw its subviews itself.
- [x] 6.3 `make screenshots` gains the page for `docs/images/`, and the README
      and `docs/index.html` describe it.

## 7. Before finishing

- [x] 7.1 `make test`: 4,336 tests in 555 suites, every new suite green.
      The full run under load 42 lost one draw.io live-editor test
      (`openingAFileIsNotEditingIt`, a web view under load, nothing of this
      change's) which passes on its own; the one timing here is behind
      `Stopwatch.maySay` and prints `MachineLoad.said`.
- [x] 7.2 `make warnings` clean: no Swift warnings, every new file under the
      length ceiling, and the four recorded files that grew — the delegate,
      the editor group, the navigator, the launch options — re-recorded with
      the reason beside each in `Scripts/file-size-allowed.txt`. The drop hook
      was taken out of the editor area again rather than recorded: the drop
      view asks its window directly.
- [x] 7.3 The three new specs and the `screenshots` delta validated with
      `openspec validate`. No `.abydos/backlog/spec/*.md` file is made untrue:
      `diff-selection`, `picture-diffs` and `git-pages` say what they said.
