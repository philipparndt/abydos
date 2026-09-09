## Why

**Two things on disk cannot be put beside each other.** Every diff this app
draws is git's: a file against its last commit, a commit's changes, a pull
request's hunks, the change marks in the gutter. Ask it the older question —
*what is different between this file and that one, between this folder and that
one* — and there is no answer. The two directories a `git difftool --dir-diff`
hands over, the two checkouts of a library somebody is upgrading, the config
that works on one machine and not on the other, the `Package.swift` a script
generated against the one in the repository: each of them is opened in two
tabs and read by eye, and the eye is the least reliable diff there is.

What is asked for is the classic two-pane comparison tool — the shape every
one of them has had for decades, from FileMerge and Beyond Compare on — drawn
the way this app draws things. The pictures that came with the ask showed one
such tool and are not kept here; they are somebody else's product and its
sample data, and nothing in them is novel. Read for what they ask of this app,
they say three things:

- **A diff of two whole files should be readable without counting.** Both
  files entire, not a patch's hunks; the unchanged stretches folded away with
  their length said; a line that moved joined to where it went, so the eye
  follows a curve instead of matching numbers across a gutter; the characters
  that differ inside a changed line marked, so a comma is a comma; the changes
  numbered, walked one at a time, and totalled in the title. And the file's
  own history beside the diff, so that any two points in its life are the two
  sides by clicking, and a commit is a page away. Here, `DiffView` draws what
  a patch contains — hunks with three lines around them, or the whole file
  spliced back in when `WholeFileDiff` can — and there is no change-to-change
  navigation and no way to choose two revisions.
- **What is compared should be a choice, not a fixed pair.** A page can hold
  more things than it compares — three drafts of a text, say — and which two
  are the sides is chosen on the page. Nothing here compares two things that
  are not a file and its own last commit.
- **Two folders should diff the way two files do.** The trees side by side and
  aligned by path, every row saying whether it differs, matches, exists on one
  side only or is ignored, the matching rows hidden and counted rather than
  listed, the names filterable — and the difference *actionable*: a row marked
  to be copied one way or the other, or removed, and all of it applied at once
  rather than file by file.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
asked for on 2026-09-08, with the three pictures. The nearest prior work is
`picture-diffs`, which put two pictures side by side with three ways of looking,
and `diff-selection`, which made a diff something code can be taken out of;
both are kept as they are.

## What Changes

- **A compare page.** An editor tab holding a shelf of sources — a file or a
  folder on disk, or either at a commit — of which one is A and one is B. The
  title names both and counts what differs. Opened by selecting two rows in the
  project tree and choosing *Compare*, by dropping a second file or folder onto
  an open file, from the file's history, and from the command line.
- **A file diff of two whole files**, side by side, with a curve between the
  halves joining each change to its counterpart, the characters that differ
  inside a changed line marked, *Change n of m* and keys to walk them, and the
  two sides scrolling together. Text is selected and copied the way
  `diff-selection` says.
- **The file's history down the side of the page**, one row per commit with A
  and B chips, so any two revisions of the file are compared by clicking, and
  a row opens the commit on the log page it already has.
- **A folder diff**: two trees aligned by relative path, each row *different*,
  *equal*, *unmatched* or *ignored*, equal rows hidden until asked for, the
  counts in the title, a filter over the names, and a click on a file row
  opening the file diff in the same tab. What is different is decided by
  size first and by bytes only when sizes agree, on a background queue, so a
  tree of a hundred thousand files is walkable before it is fully compared.
- **Copying between the two folders**, marked row by row in the gutter and done
  on *Apply*: a file overwritten or removed goes to the Trash first, so every
  apply can be undone from the Finder, in the spirit of `git-safety`'s backup
  ref. A side that is a commit is read-only and only ever the source of a copy.
- **`abydos-diff A B`** on the command line, installed by `make install-cli`,
  which also makes the app a `git difftool`, including `--dir-diff`, which is
  where the folder diff earns its keep.
- **Not proposed: a three-way merge.** The shelf may hold three documents, as
  the second picture shows, but two of them are compared at a time. Merging
  with a base is a different page with different arithmetic, and the conflict
  files git leaves already have one.
- **Long lines wrap in the diff when they wrap in the editor.** A diff of
  prose, or of a lockfile with a line a screen wide, is read the same way the
  editor reads it: ⌥⌘Z's word wrap applies here too, a wrapped pair of lines
  is one row as tall as its taller half, and the curves and the change count
  are unchanged by it. `DiffView` keeps scrolling sideways, because its rows
  are a patch's and this is not a change to it.
- **The folder diff stays live.** Both folders are watched the way the project
  tree is, so a build that writes into one side, or a file saved in another
  window, moves its row without the page being reopened. Only the directories
  the event names are listed again, and the comparison cache means a file
  that did not change is not read again.

## Capabilities

### New Capabilities

- `compare-page`: what a compare tab is — its sources, the shelf, the A and B
  chips, the history rail, how it is opened from the tree, by dropping, from
  the history and from the command line, and what its title says.
- `file-diff`: two whole files side by side — how rows are aligned, the curves
  between them, the marking inside a changed line, walking from change to
  change, the counts, and what scrolls with what.
- `folder-diff`: two folders aligned by path — the four states a row can be in,
  what decides them and what that costs, what is hidden and filtered, and the
  marking and applying of copies and deletions.

### Modified Capabilities

- `screenshots`: a driven run can open a compare page over two paths and walk
  its changes, so the pictures for the website and the tests that check the
  page are taken the way every other page's are. Nothing it says today becomes
  untrue.

## Impact

- `Sources/AbydosKit/Text/` gains a line diff with an intraline pass —
  `TextDiff` — because `GitPatch` parses a diff git wrote and there is no git
  between two files on disk.
- `Sources/AbydosKit/Project/` gains `FolderComparison`: the walk, the
  alignment, the states, the ignore rules, the byte comparison and its queue.
- `Sources/AbydosKit/Git/` gains the two read-only sources — a blob and a tree
  at a commit — read through `GitBlob` and `git ls-tree`, never unpacked into a
  temporary directory.
- `Sources/AbydosApp/` gains the tab, the file and folder views, the shelf, the
  rail and the copy gutter, as new files: `DiffView` is at the length ceiling
  and stays what it is, a patch drawn for staging. The row drawing, the
  character selection (`DiffTextRun`) and the colouring (`DiffHighlighter`)
  are shared, not copied.
- `Scripts/abydos-diff` and `Makefile`'s `install-cli`; `LaunchOptions` and the
  `abydos` script's OSC verb gain *compare*.
- README and `docs/index.html` gain the page.
- No new dependency. No change to `diff-selection`, `picture-diffs` or
  `git-pages`.
