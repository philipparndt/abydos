# 455. The commit view is a flat list where the project is a tree

`ChangesPane` is an `NSTableView` — one row per changed file, each showing a
path. On a project of any size that is a long column of near-identical strings
whose differences are in the middle, and staging a directory means selecting
every file under it by hand.

It should be a tree of the folders, relative to the repository root, and
**staging a folder stages everything under it.**

## The cheap half is already there

`GitWorkingCopy.stage(paths:in:)` runs `git add -A -- <paths>`, and `git add`
has always taken a directory. So folder staging costs nothing at the git layer —
it is one path instead of forty in the same argument list, and `-A` already
means a deletion under that folder is staged as a deletion. `unstage` is the
same shape.

**The whole of this item is the view.**

## What has to be decided

- **Which folders exist.** Only the ones with a change under them, or the whole
  project? Only-changed keeps the tree short, which is the point; it also means
  the tree changes shape as files are staged, and a folder that empties has to
  go somewhere sensible rather than vanish under the cursor.
- **What a folder's checkbox says when it is half staged.** Git has no such
  state — a folder is not a thing git tracks — so this is ours to define, and
  the mixed state has to be visible or somebody will stage a folder believing it
  was already whole.
- **Whether folders collapse to one row.** `Sources/AbydosKit/Git/` with a
  single change under it is three rows of nothing. The navigator does not do
  this, so doing it here would be a difference between two trees in one window.
  Probably not, but say so.
- **Where the tree state lives.** Expanded folders across a refresh, and
  `refreshGitStatus` runs on every filesystem change — the pane must not
  collapse under somebody mid-review. `TreeSelection` already solves exactly
  this for the navigator, keyed on paths across a rebuild, and should be reused
  rather than re-solved.

## Worth knowing

The navigator is the model for how a tree behaves in this app: selection across
a rebuild, keyboard expansion, and multi-selection are all settled there. This
should read like that rather than like a second idea about trees — and 0446
found the cost of getting the rebuild wrong at scale, which is the other reason
to take the existing answer.

Not in this item: staging *hunks*, which `GitPatch.stage` already exists for and
is a different gesture at a different granularity.

## What was decided, and what it cost

`images/changes-flat-before.png` and `images/changes-tree.png` are the same
change set before and after: eleven unstaged files across nine folders, two of
them staged, one of those also edited again since.

**Which folders exist: only the ones with a change under them.** The shape is
built in `GitChangeTree`, in the kit, so that which folders exist and what each
one says are claims the suite can check — the pane is in the app target, which
it cannot reach.

**How much of a folder is staged: a count.** `6` when all of what changed under
it is on this side, `4 of 6` in the modified colour when it is not, and a
sentence on the tooltip. There is no checkbox to give a mixed state to and
there was never going to be one — the pane is deliberately two lists rather
than one with ticks, which is what lets it show a file that is in both.

*Entries* are counted rather than paths. A file staged and then edited again is
one path in both lists; counting paths made its folder read `1 of 1` and call
itself whole while a commit would have left the second edit behind. Counting
entries makes it `1 of 2` on both sides, with no special case anywhere.

**Single-child chains are not collapsed** — as the item guessed. It costs more
than it sounded like it would: the tree in the screenshot is 26 rows where the
flat list was 11, because 15 of them are folders and most of those have one
child. That is the honest price of the structure, and it can be folded away by
hand, which is remembered. The reason for paying it stands: a folded row would
not be a folder, and it would take away the row that stages the outer folder on
its own, in a window whose other tree does not fold anything.

**Expansion is kept the negative way round** — a set of folders shut by hand,
so a folder that appears while somebody is working arrives open. The trees
arrive unfolded for the same reason `StructurePane` does: an outline that has
to be unfolded before it says anything is slower to read than what it replaced.

## Ruled out on the way

**A set of collapsed folders built from `didCollapse` notifications.** Folding
one folder posts `didCollapse` for every folder *under* it as well — they have
stopped being displayed — so the set said somebody had shut six folders when
they had shut one, and opening it again gave back a folder whose insides were
all closed. Fixed by asking the view instead: before each rebuild, walk the
*visible* rows and record which folders are not expanded. A folder inside a shut
one is not a row, nothing can be said about it, and whatever it was last seen
doing it keeps doing.

**Passing the side of the index as `inout`.** `reloadData()` asks the data
source for its rows while it runs, and the data source reads the very property
being exclusively held. Swift traps on it, at launch, every time.

**The pane surviving at all.** Two days of this looked like the tree folding
itself up a second after it was unfolded, and it was not the tree: opening a
window on the changes pane built it up to *three* times — the sidebar asks for
it, the wait queued before the repository was read installs it again, and
finishing the read installs it a third time. Each was a new `ChangesPane` and
took the last one's state with it. The commit message half typed into the pane
went the same way and always had. Two guards in `MainWindowController`, each
saying what the comment beside it already claimed, and it is built once.

## Not proved

The pane cannot be reached from the suite, so what is claimed about the *view*
— expansion surviving a rebuild, where the selection lands, what git is handed
— was driven through `--changes-tree` against a scratch repository and read off
the app's own output, three runs each. `GitChangeTree` itself has a suite.

Nothing was measured on a change set of hundreds of files. 0446's lesson was
taken as a design rule rather than re-measured: the tree is rebuilt whole and
put back by path, which is what the navigator does.

## Steps

- [x] The changes are a tree of folders relative to the root, only where there
      is a change
- [x] Staging and unstaging a folder acts on everything under it, through the
      one path `git add` already accepts
- [x] A part-staged folder says so
- [x] Expansion and selection survive a refresh, using `TreeSelection`
- [x] Multi-selection across files and folders does the obvious thing
- [x] Seen by eye on a project with a deep change set
- [x] Write down here what was ruled out on the way
- [x] `spec/<capability>.md` says what the project now does
