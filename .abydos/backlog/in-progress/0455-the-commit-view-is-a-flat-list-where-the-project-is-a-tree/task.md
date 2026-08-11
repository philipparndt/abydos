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

## Steps

- [ ] The changes are a tree of folders relative to the root, only where there
      is a change
- [ ] Staging and unstaging a folder acts on everything under it, through the
      one path `git add` already accepts
- [ ] A part-staged folder says so
- [ ] Expansion and selection survive a refresh, using `TreeSelection`
- [ ] Multi-selection across files and folders does the obvious thing
- [ ] Seen by eye on a project with a deep change set
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
