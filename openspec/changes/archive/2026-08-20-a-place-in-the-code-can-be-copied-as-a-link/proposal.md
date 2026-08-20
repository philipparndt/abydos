## Why

**A place in the code is the unit of every conversation about code, and this app
has no way to say one.** Somebody looking at line 2324 of `CodeView.swift` who
wants to hand it to an assistant, send it to a colleague or keep it for Monday
has to read the number off the gutter and type the path from memory.

The shape is already the currency everywhere else in this program.
`ReviewSession` formats its findings as `path:line` with a comment saying why —
"so the paste is useful in another tool". `Scripts/abydos` learnt `path:line`
and `path:line:column` because that is what grep, a stack trace and a compiler
error all look like. Claude Code prints `file:line` because a terminal makes it
clickable. Every one of those is something *else* producing a reference into
this project; the editor, which is where somebody is actually standing when they
want one, produces none.

Two audiences want two different strings, which is the whole reason this is not
one menu item:

- **An assistant, or a terminal**, wants `Sources/AbydosApp/Editor/CodeView.swift:2324`
  — repo-relative, no host, no scheme, and already openable by `abydos`.
- **A person**, and a bookmark for later, wants a forge permalink pinned to a
  commit: `https://github.com/owner/name/blob/<sha>/path#L2324`. A link into a
  branch rots the next time somebody edits above the line; a link into a commit
  does not.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
asked for on 2026-08-20.

## What Changes

- **A line can be copied as a reference** — repo-relative `path:line`, from the
  editor's context menu and from a keystroke. A selection is copied as a range.
- **A line can be copied as a permalink** — the forge URL for the file at a
  commit, with the line as a fragment. `GitForge` already builds a repository's
  web URL from its remote; this is that plus a commit, a path and a line.
- **A permalink says what it cannot promise.** A commit that is not on the
  remote is a link the recipient cannot open, and a file with uncommitted
  changes is a line number that means something different on the forge than it
  does on screen. Both are said at the moment of copying, not discovered by the
  person on the other end.
- **A link this app is given is re-found rather than followed blindly.** A line
  number ages: text was inserted above it, the function moved, the file was
  reformatted. Where the app can tell — its own permalink naming a commit that
  is in this checkout — it maps that historic line to the line that text is on
  now, and says that it moved. `BreakpointAnchors` already does exactly this for
  breakpoints and is the machinery, not a second copy of it.
- **Not proposed: an `abydos://` URL scheme.** A clickable link that opens this
  app means registering a scheme in the bundle and treating an inbound URL as a
  command; it is a larger thing than a copy, and both strings this change
  produces are useful to somebody who does not have the app.
- **Not proposed: putting the anchor into the copied string.** An anchor in the
  text is what makes a reference unreadable, and unreadable is the one thing
  `path:line` must not be. Re-finding is what the app does when it *opens* one.

## Capabilities

### New Capabilities

- `code-links`: saying where a place in the code is, in a form something else
  can use — what the two forms are, what each promises, what is said when a
  promise cannot be kept, and what happens when one is followed back later.

### Modified Capabilities

<!-- None. `version-control` says what a checkout and a branch are and what push
     reports; none of that changes. `editor` is about editing gestures. -->

## Impact

- `Sources/AbydosKit/Git/GitForge.swift` — a URL for a file at a commit, and the
  line fragment each forge spells its own way.
- `Sources/AbydosKit/` — a new type for the reference itself, so its shape is a
  suite's to hold rather than a screenshot's.
- `Sources/AbydosApp/Editor/` — the gestures, and what is said when a link
  cannot promise what it looks like it promises.
- `Sources/AbydosKit/Debug/BreakpointAnchors.swift` — reused for re-finding a
  line, unchanged.
- `Scripts/abydos` — already understands `path:line`; this is the other end of
  that road and nothing there needs to change.
