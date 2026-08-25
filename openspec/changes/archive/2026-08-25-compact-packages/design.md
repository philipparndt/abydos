## Context

The tree is `FileNode`s in an `NSOutlineView`. A node reads its directory on
first access to `children` and caches the listing against the directory's
modification time, so the tree lists only what somebody has expanded. Four
things walk the tree by hand and all four would meet a folded row: saving and
restoring expansion by path, revealing a file the editor opened, and the
watcher's `loadedNode(for:)`, which stops at the first closed door on purpose.

Nothing about the tree is wrong. Five rows where one would do is the whole of
the complaint.

## Goals / Non-Goals

**Goals:**

- One row for a chain of directories that each hold exactly one directory.
- `com.example.myapp` where that is what it means, `src/main/java` where it is
  not.
- Everything that works on a directory row works on a folded one.
- The walk is in `FileNode`, so it is testable without a window and both the
  outline and the four hand-written walks ask the same question.

**Non-Goals:**

- Folding a directory that holds one *file*. `src/main/resources/logback.xml`
  is a file in a directory, not a package, and the row it is on is the row
  somebody clicks.
- Knowing what a Java package is. There is no source-root model in the tree and
  building one for this would be the larger half of the change.
- Folding in the changes pane, the usages list, or anywhere else that draws a
  path. They show paths, not trees.
- Compaction on by default.

## Decisions

### A folded row *is* the last node in the chain

The row stands for the deepest directory, with a name assembled from the chain
above it. Its contents are that directory's contents, so expansion, selection,
the context menu, rename and drop all act on the thing they appear to act on
without a single special case.

The alternative — a synthetic node holding the chain — was rejected on the four
walks: `loadedNode(for:)`, `node(for:)`, `expandedPaths()` and `expand(node:matching:)`
all key on `url.path`, and a node whose URL is not a real directory would need
each of them taught about it.

### The name is recovered by walking up, not stored

`FileNode` gains `compactedName`: walk up from the node while the parent is a
directory holding exactly this one entry, collecting names, and join them. No
state to keep in step with the tree, and it is exactly the inverse of the walk
that produced the row — so the two cannot drift.

### The separator is decided by where the chain begins

Dots when the chain starts immediately below a directory named `java`, `kotlin`
or `scala` — the Maven and Gradle source-root convention — and slashes
otherwise. So `src/main/java` folds to `src/main/java`, and the `com/example/myapp`
below it folds to `com.example.myapp`, which is what IDEA shows and what was
asked for.

**And the chain ends at one, too.** A source root is where a package begins, so
it is also where the chain above it stops: `src/main/java` is one row and the
`com.example.myapp` below it is another. Without that, the whole of
`src/main/java/com/example/myapp` folds into a single row, which is neither a
source root nor a package — and the separator rule has nothing to decide, since
no chain would ever begin below a `java`. Both spec scenarios ask for the two
rows; this is the one line that produces them.

Alternatives considered. *Always slashes* — correct everywhere, and misses the
point of the request. *Dots whenever every component is a valid Java identifier*
— folds `src/main/java` into `src.main.java`, which is wrong and was the first
thing tried on paper. *Ask the build model which directories are source roots* —
right, and it needs a source-root model the tree has not got; the path
convention gets the same answer for every project laid out the way Maven and
Gradle lay projects out, which is all of them.

### The chain stops at anything that is not exactly one directory

A directory with two entries, or with one entry that is a file, ends the chain
and is a row of its own. So is an excluded directory — `target` and `build` are
tinted for a reason and folding them into their contents would hide that.

The root of the tree is never folded away: it is the project, and its name is
the one thing on screen that says which project this is.

### Off by default, and remembered like the other view preferences

A `Settings` boolean beside `showHiddenFiles`, which is the same kind of thing:
a decision about what the tree draws, made once, kept for next time. Per app
rather than per project — `showHiddenFiles` is too, and a preference that
changed as you switched projects would be one you could not learn.

### The button is a third one in the header

`NavigatorHeaderView` already lays its buttons out from the right, so this is
one entry in two arrays. Beside Collapse All and the locate button, which is
where it was asked for and where IDEA keeps it.

## Risks / Trade-offs

- **A listing per visible directory, where today there is none.** Deciding
  whether `com` folds means listing `com`, and that is a directory read the tree
  was not doing until somebody expanded it. In a tree of a quarter of a million
  files this is the shape of change that has taken the main thread for most of a
  second before — which is what `reloadPreservingIdentity`'s comment is about.
  → Three things hold it down: the listing is cached on the node against the
  directory's mtime, so it is paid once; the walk stops at the first directory
  with anything but one entry, which is nearly all of them; and excluded
  directories are not walked at all. → And it is measured, not argued: task 5.2.

  **Measured** (`make scale`, subject `abydos`, load 8.1 over 14 cores — the
  corpus itself is not on this machine, so this repository is the subject):
  opening the root is 1 listing and 5.7 ms of processor time with compaction
  off, and 18 listings and 9.8 ms with it on — one listing per child directory,
  which is what the design says it should be. Asking the same tree again is 0
  listings and 0.1 ms, which is the cache doing what it is there for and is what
  every refresh after the first one costs. A level deeper, 339 rows cost 37
  further listings. The shape is as argued: it is paid once, per visible
  directory, and never again until something moves.

- **The four hand-written walks.** Reveal, expansion save, expansion restore and
  the watcher's reload each descend through `children`, and each would descend
  through folded rows the outline is not showing. → They keep working, because a
  folded row is a real node at a real path; what changes is that `expandItem` on
  an intermediate is a call on something the outline does not have. Each of the
  four needs a test.

- **Toggling it changes every row's identity in the outline.** → Expansion is
  saved and restored by path already, and the deepest node keeps its path either
  way; what is lost is the expansion of the intermediates, which have no rows
  when it is on. Restoring after a toggle is task 4.2.

- **A folded row can get long.** `com.example.myapp.internal.persistence.jpa` is
  wider than the sidebar. → The cell already truncates, and the tool tip already
  carries the full path.

### Turning it on folds unconditionally

The open question — whether a chain somebody has explicitly expanded should stay
unfolded — is answered no. Turning compaction on folds every chain, including the
one that is open; the row for the deepest directory keeps its path, so it is
still open afterwards and the file that was selected is still selected. What is
lost is the expansion of the intermediates, which have no rows while it is on,
and turning it off puts them back — that is what `FilePath.withAncestors` is for.

A toggle that sometimes does nothing is harder to understand than one that always
does the same thing, and there is nowhere honest to keep the exception: "this
chain was expanded on purpose" is state about rows that no longer exist, and it
would have to survive a reload, a rename and a watcher event that changes the
chain's shape underneath it.

## Open Questions

None. The one above is decided in `Decisions`.
