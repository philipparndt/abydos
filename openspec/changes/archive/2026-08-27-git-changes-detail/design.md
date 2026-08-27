## Context

A changes list is `GitChangeNode`s in an `NSOutlineView`. `GitChangeTree.build`
takes the flat list of `GitChange` from `GitWorkingCopy.status` and invents the
folders above them; the log page builds its own list from `PathTree` and shows
files only. Both the sidebar and the commit page draw from the same node type.

Two facts decide most of this change, and both are already in the code.

**`GitChange.isDirectory` exists.** Its comment says why: "The flag exists so the
row can say what it is: a diff of a directory is not a diff." The model has known
since it was written which entries are whole untracked directories. Neither view
asks.

**`GitChangeNode.isFolder` is `change == nil`.** That is the mechanism of the
reported fault, exactly: a folder is a row *the pane invented*, and an untracked
directory has a change, so it is not a folder and is drawn as a file. Nothing is
mis-read; the wrong question is being asked.

`GitWorkingCopy.contents(ofUntrackedDirectory:in:)` already lists what is inside
one such directory with a scoped `-uall`, reached today through
`diff(for:staged:in:isDirectory:)` so the diff pane can show a list where a diff
would be empty.

## Goals / Non-Goals

**Goals:**

- An untracked directory reads as a directory, and opens.
- The log page can arrange its changes by folder.
- A row says how much changed.
- `*` opens a commit's tree.
- Nothing new is asked of git on the path that runs per filesystem event.

**Non-Goals:**

- Changing what the working-copy listing asks for. `-unormal` is measured and
  stays.
- Line counts inside an unexpanded untracked directory. See the decision below;
  it would be the walk this design exists to avoid.
- Staging part of an untracked directory. It is one entry to git and one row to
  stage, expanded or not.
- A second arrangement for the sidebar. It has the folder tree already.

## Decisions

### Two kinds of folder row, and `isFolder` keeps its meaning

`isFolder` goes on meaning "a row this pane invented", because three things key
on it and all three are right to: `isPartial` is `isFolder && count < total`, the
context menu's wording, and the staging path that hands git one argument for a
prefix. A new question — `holdsFiles`, true for an invented folder *or* an
untracked directory — is what the icon and the disclosure triangle ask.

Rejected: redefining `isFolder` as "anything with files under it". It reads
better and it silently changes `isPartial` for a row that git reports as a single
entry, so an untracked directory would start claiming to be partly staged. The
count arithmetic in `GitChangeTree` is careful and load-bearing (its comment
explains why it counts entries rather than paths); this is not the place to
disturb it.

### The children are asked for when the row opens, and belong to the row

Lazily, per directory, the way the project tree loads `FileNode.children` — and
for the same reason, one level up in magnitude: `-uall` over the work tree was
seven seconds against 0.11 s, on a listing that runs dozens of times a minute
during a build. Scoped to one directory it costs what that directory holds.

Rejected: `-uall` in the listing, which is the measurement above. Rejected:
expanding every untracked directory as the tree is built, which is the same cost
under another name, paid whether anybody opens a row or not.

`contents(ofUntrackedDirectory:)` becomes public, or gains a public sibling that
returns paths rather than the text the diff pane renders. The rows made from it
are invented, all untracked and unstaged, and they are *not* added to the
directory's `count` or `total` — those come from the listing, where the whole
directory is one entry. Adding them would make a folder that git considers
whole read as "1 of 12" and offer to stage the rest of something already
staged.

### The counts come from one `--numstat` per side, not one diff per row

`git diff --numstat` for the unstaged side, `--cached --numstat` for the staged
one, `git show --numstat` for a commit: one command, one record per path, joined
onto the nodes after the tree is built. A folder sums what is under it.

Rejected: a diff per row, which is what the pane already does for the file being
looked at and is fine for one; thirty of them to draw thirty rows is thirty
processes.

Binary files, mode changes and pure renames come back from `--numstat` as `-` in
both columns. Those rows say nothing about lines rather than saying zero, because
zero is a claim that nothing changed.

**An unexpanded untracked directory says nothing about lines.** Every line of
every file under it is added, and knowing how many means walking it — which is
the cost this design is built to avoid. Once expanded its children carry their
own counts and the sum appears. This falls out of the two decisions above rather
than being chosen, and it is the one place where the "a folder row carries the
sum" requirement is answered with silence.

*Corrected while implementing:* this paragraph first said such a row would "say
how many files it holds, which is what it can answer for free". It cannot answer
that for free either — the file count and the line count are the same walk. A row
that has not been opened says neither.

### The toggle is a preference, not a per-page mode

A `Settings` boolean beside the other view preferences, so a commit opened
tomorrow is arranged the way the last one was. Per page would mean choosing again
for every commit, which is the same objection the project view's compaction
toggle answered.

The log page builds its file list itself today; the toggle points it at
`GitChangeTree.build`, which is what the sidebar has always used. One shape
built one way.

### `*` walks the rows rather than recursing the model

`NSOutlineView` has no expand-all. Expanding row by row from the top, taking
`numberOfRows` again as it goes, is what every other outline in this repository
does for this and is correct as rows appear beneath. From any row, not from the
selection down: `*` in a file manager means "all of it".

Rejected: recursing the node tree and calling `expandItem` on each — it works and
it visits nodes the view has never been handed, which is the shape of bug the
project view's compaction change spent its time on.

## Risks / Trade-offs

- **`--numstat` has no scope to be cut down to.** The untracked directory
  listing is affordable because it is per directory and on demand; a diffstat is
  the whole commit or the whole working copy. → Asked once per set of changes,
  and not again while nothing has moved. → And measured on a large commit and a
  large working copy before this is called done, because the precedent here is
  that somebody's seven-second listing was found this way and not by argument.

- **A lazily-filled row inside a tree that is rebuilt from scratch on every
  refresh.** Expansion and selection are restored by path, so an open untracked
  directory has to be re-filled after a refresh or it will collapse under
  whoever was reading it. → The same problem the project tree solved with
  `reloadPreservingIdentity`; here the answer is smaller, because the contents
  can be kept against the row's path and re-asked only when the directory's own
  mtime moves.

- **The counts double the width of a row.** A long path plus `+1234 −567` in a
  narrow sidebar leaves little for the name. → The name truncates before the
  counts do; the counts are the shorter and the more often wanted.

## Open Questions

- Should `*` work in the sidebar's changes tree as well? The request is about the
  commit tree, and the sidebar holds branches, tags and worktrees besides — where
  "expand everything" could open every ref folder in a repository with hundreds.
  Leaning towards the commit tree only, and revisiting if it feels arbitrary in
  use.
- Whether the folder toggle should also govern the *sidebar's* changes tree,
  which is folders-only today. Nobody has asked for a flat list there, so this
  proposes not to offer one — but the two views then disagree about what a
  preference named "arrange changes by folder" means.
