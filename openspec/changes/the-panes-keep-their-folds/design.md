## Context

A project's session is captured in two places —
`MainWindowController.rememberOpenEditors` and the body of `switchProject`
(`MainWindowController+Terminal.swift:363`, `:479`) — into a `ProjectSession`,
written by `SessionStore` to `.abydos/session.json` beside the project and, for
a folder in no working copy, to the one file every such folder shares. A driven
run reads none of it and writes none of it, which is a requirement of its own.

Three facts shape everything below.

**A pane is not a place to keep anything.** Every fold set in the app lives on
the view that draws it:

| set | where | seeded |
|---|---|---|
| `collapsedKeys` | `BranchesPane.swift:86` | `["working"]` |
| `openedKeys` | `BranchesPane.swift:96` | empty |
| `sectionsThatStartShut` | `BranchesPane.swift:100` | filled at build: each remote, `Tags` |
| `Side.collapsed` | `ChangesPane.swift:198` | empty, one per side |
| `Side.opened` | `ChangesPane.swift:213` | empty — untracked directories |
| `expandedPaths()` | `ProjectNavigatorViewController.swift:1065` | computed, never stored |

and `SidebarController.install(tool:force:)` sets `changesPane = nil` and
`branchesPane = nil` before building the tool again. The rebuild happens on a
project switch, after `readGit()` when the work tree changed, and when a tool
shown over the terminal is put away. So the folds are lost several times within
one sitting, not only between two.

**The two sets are not one set.** `collapsedKeys` is the negative way round —
open unless shut — which the changes tree keeps too: *"a changes tree wants to
arrive open: a pane that shows five folder names where the flat list showed
twenty files has told you less than it did before"*. `openedKeys` is the
positive way round for the two sections that are somebody else's account of
things: *"`origin` is every branch anybody has pushed and `Tags` is every
release there has ever been; unrolled, they are the bulk of the pane"*. The
untracked directories in the changes tree are positive for a third reason —
opening one costs a git call. A session that carried one list of "expanded
items" would have to guess which rule each key was under.

**The project tree already has the right shape and throws it away.**
`expandedPaths()` returns a `Set<String>` of absolute paths, `dep:` identities
and `session:` identities, and `restore(expandedPaths:)` puts it back — six
call sites do exactly this around a reload. `load(project:)` does not: it
reloads and expands the root alone.

## Goals / Non-Goals

**Goals:**

- What somebody folded or unfolded in a tree comes back, per project.
- The arrival defaults are unchanged for a project nothing has been recorded
  for.
- The tool in front and the terminal in front come back.
- Nothing new is invented for storage: the session file the project already has.

**Non-Goals — and each of these is a decision, not an omission:**

- **The settings page's section and its folded sections.** Recorded against
  them: *"Not remembered between launches, deliberately: there are seven
  sections and one of them folds, so opening settings to find a section missing
  because of something done last week costs more than folding Tools again
  costs."*
- **The search pane's query, its marks and its collapsed file headings.** The
  spec says *"Marks live as long as the window. They are not written to disk"*,
  and the pane says *"The query is a person's words: it costs nothing to ask
  again and is the thing they would type."*
- **The backlog pane's mode.** *"a pane that opens on whatever was last looked
  at is a pane that opens differently for two people looking at the same
  project, and the switch is one click."*
- **Where a results list is docked.** Ruled out per project already, by name:
  *"it would be the only thing in `ProjectSession` that is about a list nothing
  restores."*
- **A diagram's or a picture's fit.** *"Keyed by path it would need a store,
  would have to be forgotten when a file is renamed or deleted, and would open a
  diagram at a size chosen a week ago in a differently shaped window."* The
  interface zoom, which is the part somebody sets once, is already remembered.
- **The commit page's description chevron.** `git-pages` says *"The chevron's
  state SHALL be kept for as long as the page is open… a page opened afresh
  starts collapsed"*, and the layout argument behind it holds at every height.
- **The panel's non-terminal panes.** *"a debugger, a profiler or a review is
  attached to something that is not running any more, and reopening one would be
  reopening a window onto nothing."*
- **The find bar's query per tab**, emptied on purpose when the tab that
  searched closes.
- **The tmux strip's first drawn tab.** *"Not a scroll position… it is not
  remembered anywhere."*
- **A tab's scroll offset, its caret column and its selection.** The caret line
  is remembered and `reveal(line:)` centres it, so a tab comes back on the part
  of the file it was on. An offset in points restored into a pane of another
  height puts a different line at the top, which is the reason the split divider
  is a fraction and not a position; a line is the granularity everything else in
  the app is in — go to line, a breakpoint, a diagnostic — and there is no
  report that the caret comes back on the wrong one.
- **The split editor arrangement.** *"Flattened across split groups: the tabs
  come back, the arrangement they were split into does not."* That is a real
  loss and it sits on top of a known bug — `EditorAreaController.restore` only
  restores the active group, so a second group keeps the *previous* project's
  tabs. It wants the group model in the session and that bug fixed first, and
  doing it here would hide it.
- **A split panel's two columns**, for the same reason: `OpenTerminal` has no
  column and restoring one needs the splitting machinery, not a field.
- **The panel being maximised.** The panel's *height* is already per machine,
  in the split view's autosave, and how much of a window one pane has is that
  kind of thing rather than a property of the project. It is not stored at all
  today, which is a gap in the autosave rather than in the session.

## Decisions

### The folds go in the session, not in `UserDefaults`

The refs tree's sort orders went the other way, and said why: *"one choice per
kind rather than per repository… this is a reading habit, and choosing again for
every checkout is choosing nothing."* A fold is the opposite of a reading habit.
`section:origin` names a remote this repository has, `working` names a working
copy that is this project's, and a folder path names a directory in this
checkout. There is nothing in a fold that another project could use, and the
session file is the file somebody can delete along with the rest of `.abydos`.

### Both sets travel, per pane, and nothing is merged

`ProjectSession` gains a `folds` value holding, per pane, the keys shut and the
keys opened. Merging them into a single "expanded" list would need a rule for
what an absent key means, and the answer differs per pane and per section — the
whole content of the two comments quoted above. Recording exactly what the panes
hold means the arrival defaults keep working with no second copy of them in the
kit.

The refs tree's keys are the node keys it already builds and already finds rows
by after a rebuild — `working`, `section:Tags`, `section:origin`, `branch:main`,
`folder:feature`. A key rather than a path, for the reason the pane's own
selection keeper gives: *"a ref is not a file"*.

### Tree paths are relative to the project, and the tab paths stay absolute

A fold in the project tree is recorded relative to the project root. The session
file sits inside the project, so a checkout that is moved, or the same checkout
opened through a worktree, is the same tree with the same folders. The open tabs
stay absolute because a tab can be a file from anywhere — that is why they were
written that way and this does not change it.

The `dep:` and `session:` identities are already not paths and travel as they
are.

### Bounded, shallowest first

A tree somebody has walked deep into can hold thousands of unfolded folders, and
a session file is read on every project switch. At most 500 keys per tree are
kept, the ones nearest the root first: a fold near the root is the structural
one somebody arranged, and a fold twelve levels down is where they happened to
end up. Ruled out: no bound at all, which is how a `.abydos` file comes to be a
megabyte of directory names; and a most-recently-folded bound, which needs an
order the panes do not keep.

### Re-applied where a pane is built

Straight after `load(project:)` is the wrong moment and the composed message
already paid for finding that out: `readGit()` rebuilds the tool a second or two
later and the application goes with it. So each pane reads the session where it
is constructed, in `makeToolView`, exactly as the changes pane reads the
remembered message today. The project tree is not rebuilt that way and takes its
folds in `load(project:)`, where it currently expands the root alone.

### The tool comes back, the sidebar's visibility does not

`currentSidebarTool` is per project in the session. Whether the sidebar is
*showing* is the split view's autosave, per machine, and stays there: somebody
who closed the sidebar closed it for the window, not for the project, and a
restore that opened it would be the session arguing with the layout.

A remembered tool that cannot be built — the git tool for a folder in no working
copy, or a tool a later version knew about — falls back to the project tree
rather than to nothing. Ruled out: waiting for the repository before showing
anything, which is the empty sidebar the "Reading repository…" view was added to
prevent.

### The terminal in front, by name

`OpenTerminal` gains "this was the one in front". By name and not by index, for
the reason the tmux window is an id and not an index: the list is rebuilt and a
terminal that failed to start shifts everything after it. Where no restored
terminal has that name, the panel does what it does today.

### What a driven run can prove, and what it cannot

A driven run neither reads nor writes a session file, so the disk half is a kit
test on `SessionStore` — including an older file with none of the new keys.
The switch half can be driven end to end: `ProjectSessions` keeps the outgoing
session in memory keyed by root, so leaving a project and coming back inside one
run exercises capture and restore. The rebuild half — the one the report is
actually about — is reached by the same door the composed message's proof used:
a switch reinstalls the tool through `install(tool:force:)` after `readGit()`.

## Risks / Trade-offs

- [A fold restored against a branch or folder that has gone] → a key that finds
  no row does nothing, which is what a rebuild already does with a key from
  before the last filesystem event. Keys that match nothing are dropped on the
  next capture rather than accumulating.
- [Restoring the untracked directories somebody opened costs a git call each] →
  it is the call opening one costs today, made for the directories somebody
  chose. Bounded by the same cap, and made after the pane is on screen.
- [A project tree unfolding forty folders at open reads forty directories] →
  the navigator already does exactly this after every reload; what is new is
  doing it once at open, off the first paint.
- [A bigger session file] → keys, sorted, only where they differ from the
  arrival defaults, capped per tree. A file that grows is a file somebody reads
  when a session comes back wrong, which is why every other field here is
  written only when it says something.
- [Two windows on one project] → last write wins per field, as it already does
  for the editors and the message.

## Open Questions

- Whether a fold recorded in a *worktree* of a repository should be seen by the
  main checkout. They are separate projects with separate `.abydos` folders
  today, and this change keeps that; if it turns out that somebody moving
  between two worktrees of one repository wants one set of folds, that is a
  question about where a worktree's session lives and not about folds.
