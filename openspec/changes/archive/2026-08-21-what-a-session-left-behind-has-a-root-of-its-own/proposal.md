## Why

**The files an agent leaves behind are useful for weeks and findable by nobody.**
Claude Code gives every session a scratch directory of its own, and the sessions
working on this project have filled fifteen of them: reproductions, driven-run
logs, screenshots of a fault, a Go program that stops in the right place, a
throwaway checkout somebody was told never to drive against a real one. Reaching
one means knowing that it is

    /tmp/claude-<uid>/-Users-philipparndt-dev-abydos/<session-id>/scratchpad

— a path with the project's own name in it, spelled with every `/` and `.`
turned into `-`, and a session UUID nobody has memorised. Asked for this
morning, and the honest answer was a shell one-liner:

    slug=$(pwd | tr './' '--'); ls -td /tmp/claude-$(id -u)/$slug/*/scratchpad

That is a lookup, done by hand, against a directory the window already knows the
key to.

**The project view already solved this shape of problem once.** *Dependencies*
shows what a project is made from — files that are emphatically not in the
project's directory — as a root of its own, read from what is on disk, listing
lazily, with every file row behaving like any other. What a session left behind
is the same kind of thing: not part of the project, worth reading beside it, and
answerable without running anything.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
asked for on 2026-08-21.

## What Changes

- **A third root in the project view**, beside the project's own files and
  *Dependencies*: **Claude Sessions**, one row per session that has left
  something behind for this project, newest first.
- **A session's row is a directory row.** Its children are the files in that
  session's scratchpad and its `tasks/` output, and everything the tree does with
  a file it does with them: they list lazily, they open, the arrow keys walk
  them, and a file opened from one is revealed there.
- **A row says which session it was**, because a UUID does not: when it last
  wrote something, how much is in it, and the first thing that was asked of that
  session — read from the head of its transcript rather than from the whole file,
  which for the session writing this proposal is twenty megabytes.
- **The root appears only when there is something in it**, the rule
  *Dependencies* already keeps: a project no agent has worked on has two roots,
  not three with an empty one.
- **Read-only, and nothing is run.** Another program's directories are read and
  never written, the way the dependency sections read a lock file and never a
  build tool.
- **Not proposed: putting this under `Dependencies`.** It is not something the
  project depends on. `DependencyTree` argued *against* a third root when the
  toolchain rows were added, and the design answers that argument rather than
  ignoring it.
- **Not proposed: opening a transcript as a file.** A twenty-megabyte JSONL in
  the editor is not reading a conversation.
- **Not proposed: deleting a session's files from the tree.** Reclaiming `/tmp`
  is a different gesture with a different risk, and this one is for finding
  things.

## Capabilities

### New Capabilities

<!-- None. The tree's roots are `project-view`'s subject and adding one there is
     a change to what that capability already says. -->

### Modified Capabilities

- `project-view`: its first requirement opens "The tree has two roots", which
  this makes untrue. It gains the third, what a row under it is, when the root
  is there at all, and what reveal does with a file that lives in one.

## Impact

- `Sources/AbydosKit/Project/` — where a session's directories are found for a
  project, and the slug that keys them. Pure, and testable without a tree.
- `Sources/AbydosApp/Navigator/` — the root, its rows, and the reveal that
  claims a file inside one.
- `Sources/AbydosKit/Project/DependencyTree.swift` — untouched, and its argument
  against a third root quoted in the design and answered.
- No new dependency, no network, nothing run.
