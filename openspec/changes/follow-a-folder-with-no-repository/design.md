## Context

See proposal.md — Why, for the motivation and the two items whose reasoning this
touches.

What shapes the approach is that three of the four pieces already exist and only
one of them refuses. `TerminalDirectory` reports any working directory it is
given; `BottomPanel.reportWorkingDirectory()` passes it on; `Project` already
holds `git` as an optional and a plain folder is already a first-class project,
opened by ⌘O and by `abydos <dir>` with no check of any kind. `ProjectRoot` is
the only part that says no, and it says no by returning nil.

Two constraints come from the code rather than from taste. `switchProjectBody`
writes a session beside the project it leaves and, arriving somewhere with no
stored session, calls `editor.closeAllTabs()` — so anything that makes a
directory a project makes those two things happen on a `cd`. And the containment
test at the top of `projectToFollow` means a window can only ever widen: once it
is on an ancestor, every directory under it is "inside the project" and no `cd`
narrows it back.

## Goals / Non-Goals

**Goals:**

- Following works for Subversion and Mercurial checkouts the way it works for git
  ones, at the checkout root.
- A shell in a folder under no version control takes the window there.
- Nothing is written into a folder somebody merely walked through.
- Files stay open while somebody moves around such folders.

**Non-Goals:**

- Reading Subversion or Mercurial state — no branch, no status, no history. Only
  the question "which directory is the root" is being answered, from the
  filesystem, with no subprocess.
- Changing any explicit way of opening a project. ⌘O on a plain folder behaves
  exactly as it does today.
- The project switcher's "All Projects" disk scan, which is git-only for its own
  reasons (`ProjectDiscovery.isProjectRoot`, and a `lastActivity` that stats
  `.git/index`). Widening it is a separate change.

## Decisions

### A folder in no working copy is not a project

The central decision, and the one that makes the rest small. Every other shape
tried had to answer "when does a `cd` inside a plain folder re-root the window",
and this one deletes the question: there is no project to be inside.

**Ruled out — every directory is a project, keeping the containment rule.** The
ratchet. `cd ~` makes `~` the project, and `cd ~/notes` is then *inside* it, so
the window is stuck on the home directory until somebody opens a project by
hand.

**Ruled out — every directory is a project, dropping containment for the ones
with no marker.** This fixes the ratchet and reintroduces 0509. A folder of
notes opened deliberately, with three files open, loses them to a `cd` into a
subdirectory, because the subdirectory has no stored session and
`switchProjectBody` closes the tabs. The gesture that means "going about my
work" inside a checkout would mean "throw away my tabs" inside a folder, decided
by whether a `.git` happens to sit above.

**Ruled out — a flag separating a project somebody chose from one the window
drifted into**, so containment applies to the first and not the second. It works,
and it is one boolean, but it keeps a folder being a project — so the `.abydos`
files still land in it and the recents list still fills with directories nobody
opened. Not being a project gets both for free.

### The markers are the version-control roots, plus `.abydos`

`.git` (with the existing submodule-versus-worktree rules), `.svn`, `.hg`,
`.abydos`/`.ideai`.

**Ruled out — `Subprojects.markers`**, the list holding `go.mod`, `pom.xml`,
`Package.swift`, `CMakeLists.txt`. Climbing finds the *nearest* marker, so
`cd repo/service/src` in a multi-module Maven checkout would root the window at
`repo/service` — which is not a project switch, it is the window losing the
checkout. That list is the scope mechanism *inside* a project, which is what
`Subprojects` is for, and using it for identity as well would have the two
fighting.

`.abydos` earns its place differently: it is not a build file but this
application's own note that somebody opened this folder as a project, and it
only ever appears where somebody did. A folder that was opened once is a project
the next time a shell walks into it. Deleting the folder undoes it, which is the
right escape hatch for one opened by accident.

### The marker test answers where the shell has gone, never what may be opened

Explicit opens — ⌘O, `abydos <dir>`, drag and drop, Finder, the recents list —
keep making a real project of a plain folder, marker or no marker. Two reasons.
It is a deliberate act and the app has no business second-guessing it; and it is
what writes the `.abydos` that makes the folder a marker root afterwards. Had the
marker test governed opening too, a folder deliberately opened would never get
one written, so it could never become a project, and it would re-root on every
`cd` — the failure above, reached by another road.

A consequence worth naming: such a folder is a project for that sitting because
the open said so, and a project on later sittings because the marker says so.
The two agree as soon as anything is written, which `rememberOpenEditors` does on
the next tab change.

### Containment still applies whenever there is a project

Unchanged, and it is what protects the case above. A folder inside the project
the window is on is not a move, whatever markers it has. No ratchet can form,
because the only way to widen was to be contained by an ancestor *project*, and
walking out of a project now drops to a folder rather than to an ancestor.

### A `.svn` is read to find out which kind it is

Subversion 1.7 and later keep one `.svn` at the working-copy root, holding
`wc.db`. Before that, every directory had one, so "the nearest `.svn`" means
"the directory I am standing in" and would root the window at `src`. So: a `.svn`
holding `wc.db` is a root and stops the climb; one without it is an interior
directory, remembered while the climb continues, and the topmost wins.

**Ruled out — treating `.svn` exactly like `.git`.** Correct for any client from
2011 onwards and wrong in a way nobody would diagnose for anything older, and the
difference is five lines. It is also the move `isSubmodulePointer` already makes
next door: two things that look alike, told apart by what is inside them.

### `projectToFollow` answers with a decision, not an optional URL

`enum Move { case stay, project(URL), looseFolder(URL) }`.

The alternative is `(URL, Bool)` or two functions, and both make the caller
reconstruct which of three cases it is in. Three cases is what there are, and the
window switches on them.

### A session lives at `URL?`, nil meaning the one shared session

`SessionStore.read`/`write` take an optional root. This is not a new convention:
`OpenScratches.key(for:)` is `projectRoot.map(ScratchFiles.directoryName(for:))
?? ScratchFiles.globalDirectoryName`, `ScratchEntry.projectRoot` is documented as
"the project it belongs to, or nil for a global one", and `RecentProjects`
already writes into the Application Support directory the shared session will
use.

**Ruled out — a second pair of functions** (`readGlobal`/`writeGlobal`). Two
functions that differ only in where the file is, called from the same four
places, each of which would have to decide which to call.

### A move between two such folders skips the session machinery entirely

Not "capture and restore the same session", which would be a tab set torn down
and rebuilt to what it already was. `load(project:)` only: the tree, the search
and the file index re-point and nothing else is touched. The two halves of
`switchProjectBody` are already separable — the capture/write/restore dance, and
the `load` — so this is a route through it rather than a new mechanism.

## Risks / Trade-offs

**Language servers restarting on every `cd` through a folder tree** → A server
that declares no root markers is rooted at the project root unconditionally
(`LanguageServers.markerDirectory`: `guard !definition.rootMarkers.isEmpty else
{ return root }`), and item 0427 records that stopping one costs a re-index.
Servers that do declare markers will not start in a plain folder at all, so most
of them are unaffected. Measure it before deciding whether a folder should start
any server; the fallback is that it starts none, which costs nothing that a
folder under no version control was likely to want.

**One shared session, two windows** → Two windows both showing folders share it,
and the last to write wins. The same shape as two windows on one project today,
which nothing has complained about; it is easier to reach here, and worth
watching rather than designing against now.

**`.abydos` makes a folder a project for ever** → A folder opened once by
accident keeps being one. `rm -rf .abydos` undoes it, and that is a smaller
surprise than a folder deliberately opened refusing to stay a project.

**Leaving a project now does something where it did nothing** → `cd /tmp` from a
checkout costs nothing today; it will put the checkout's session away and show
the folder. That is the point of the change, but it means a habit of `cd /tmp
&& … && cd -` becomes two switches. The files come back, so the cost is time
rather than work.

**Opening a very wide folder as a project was sticky, and is not any more** → `.abydos` counting as
a marker means a folder somebody opens deliberately stays a project afterwards,
which is the point — but for a folder as wide as the home directory it is a trap.
Once `~/.abydos` exists, a markerless directory anywhere under it resolves to
`~`, the window takes `~` as its project, and the containment rule then holds
every directory below it: nothing moves again. The containment rule is older than
this change and behaves the same way for a git checkout opened at `~`, but making
`.abydos` a marker is what puts the trap within reach of one ⌘O. The sharper reading of "inside the project" is what fixes it, and it is
now the rule: containment wins *unless* the marker root found is itself strictly
inside the current project. That switches into a nested checkout while still
refusing 0509's outward move — the checkout a package sits in is an ancestor, not
a descendant — and leaves submodules alone, `find` already resolving those to the
repository around them.

**A folder is a project as far as the tree is concerned and not as far as the
session is concerned** → Two notions of "project" in one window, which is a real
seam. It is narrowed by putting the distinction on the project itself rather than
on the window, so that everything asking "where does this session go" and "should
this be a recent" reads one property.

### One classification, reached by both reports

Two things report where a pane is: a shell that changed directory
(`terminalDirectoryChanged`) and a pane brought forward carrying the root it was
made under (`onPaneNeedsProject`). Both go through one `follow(reported:)`.

**This was found the hard way, by the first person to use it.** The second caller
was left switching straight to a *project*, so a pane created while the window
showed a folder carried that folder as its root, and bringing the pane forward
made a project of it: `.abydos` written into it, a recents entry, and — the
folder being the home directory — every directory underneath it then counted as
inside the project, so no later `cd` moved the window at all. It presented as
"the folder navigator is stuck on my home folder", and the `.abydos` left behind
would have kept it stuck across a restart. Whether a directory is a project is
not the pane's to say, and now no caller says it.

## Migration Plan

None to run. The shared session file does not exist until something writes one,
and reads as "nothing was open", which is the same answer a project with no
session gives today. Nothing is written into anybody's folders by the change
itself, and the `.abydos` folders that already exist beside deliberately-opened
plain folders start counting as markers, which is the behaviour they should
always have had.

Reverting is reverting: no data is moved and no format changes.

## Open Questions

- Whether a folder that is not a project should start any language server at all.
  Deferrable: it changes no requirement and no task, and the honest way to decide
  it is to measure a `cd` through a tree with a server running.
- Whether the titlebar should say, and not merely imply by the absence of a
  branch, that what it names is a folder rather than a project. A question about
  what somebody reads at a glance, best answered by driving the app and looking
  at it.
