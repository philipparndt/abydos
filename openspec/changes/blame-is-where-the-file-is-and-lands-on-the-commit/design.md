## Context

`GitBlame.lines(for:in:)` runs `git blame --line-porcelain -- <path>` and
parses it into one `Line` per line — commit, author, date, summary, and
whether the line is uncommitted. `CodeView` draws the column and, on a click,
calls `onShowBlameDetail` with the entry; `EditorViewController` answers that
with a toast. `toggleBlame()` is the one implementation the View menu, ⌥⌘B
and the gutter's item all reach through the responder chain.

The log page is `HistoryPane`, opened by `SidebarController.showLogPage(scopedTo:)`
with a ref that becomes `git log <ref>`, and it can be narrowed to a path
with `setScope(path:)`. Its first row is then the commit named, and selecting
a row shows the commit's message and its diff. The tree's file menu and the
tab bar's menu each have a callback per verb, added the way *Open as Hex* was.

## Goals / Non-Goals

**Goals:**

- Blame reachable from the file, wherever the file is: the tree, the tab, the
  palette.
- A click on a blame entry landing on the commit, in the page the app already
  has for commits.
- Moved code keeping its author, and a formatting commit not owning the file.
- A spec.

**Non-Goals:**

- Blaming the parent of the clicked commit, inline blame, hover cards, age
  colouring, `git log -L` for a selection. Wanted, and a second change.
- A blame view of its own. The column is the view; the log page is the
  commit's.

## Decisions

### *Blame* on the file's menus opens the file and turns the column on

The tree's file row and the tab's menu get *Blame*. On a file that is not
open, it opens it first, pinned, then turns the column on — one gesture for
"who wrote this file", from the row the question was asked at. Through the
menus the palette finds it by name, which is where the colleague looked. It
is *Blame* and not *Toggle Blame*, since from a row it only ever turns the
column on; the gutter's item keeps its two words because there it is the
switch.

*Ruled out:* a blame page or window. Two places to read the same column is
two things to keep in step.

### A click goes to the log page, scoped to the file, at the commit

`onShowBlameDetail` becomes `onRevealCommit(commit, file)`. The window opens
the log page scoped to the commit's hash — `git log <hash>` puts the commit
first — narrows it to the file, and selects the first row, so the message
and the diff of this file at that commit are on screen. That is the answer
to "what was this change", which the toast only named.

An uncommitted line has no commit: the toast stays for that one case and
says the line is not committed yet.

*Ruled out:* a popover on the column with the message and a button. It would
be a third rendering of a commit, beside the log row and the commit page.

### `-M -C`, and the ignore file when it is there

`git blame -M -C` attributes moved and copied lines to their origin, which is
what every other blame view shows and the only reading under which "who
wrote this" is answered. `--ignore-revs-file .git-blame-ignore-revs` is passed
when that file exists at the repository's root, since git refuses a missing
one; a `blame.ignoreRevsFile` set in config is read by git itself and is not
repeated. The arguments are a function of the root, so a test reads them
without running git.

*Ruled out:* always passing the flag and swallowing the error — a repository
whose file is named differently would then blame nothing, silently.

### The spec is new

`git-blame` is written as a capability, since nothing described the column,
and the three doors, the click and the flags each get a scenario.

## Risks / Trade-offs

- [`-C` cost on a large file] → one `-C` looks for copies within the same
  commit only; the pass is still one `git blame` per toggle, and blame is
  turned on per file by hand.
- [The log page not open on a project without git] → *Blame* is offered only
  where the file is in a repository; the click without a git root keeps the
  toast.
- [The first row not being the commit] → `git log <hash>` starts at the hash
  by definition; if the scope to the path drops it (a commit that did not
  touch the file, which blame cannot name), the page is shown scoped without
  a selection, which is still the file's history.

## Open Questions

None: the pieces exist and the shapes are the ones the other doors use.
