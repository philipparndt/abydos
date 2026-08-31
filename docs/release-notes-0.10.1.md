# Abydos 0.10.1

Three commits the day after 0.10.0, and a point release for the reason 0.8.1's
notes give: no single one of them is worth a version of its own. It is the same
release 0.10.0 was, continued — the git pane, and nearly every item in it named
after a direct report from somebody looking at the pane while using it, each one
with a screenshot attached. Five requests came in on 2026-08-31 and all five are
here.

The one item that argued for a version of its own is the change marks in the
editor gutter, which is a thing the editor could not do at all before. It is here
rather than in 0.11.0 because holding five reports back for a week to keep one of
them company helps nobody.

## The log page shows what the upstream has

A log scoped to a branch showed that branch's ancestry and nothing else, because
that is the one revision `GitHistory.log` was given. So a repository whose own
header said `1 behind · 2 ahead` opened `Log · main` on a page with no trace of
the commit `origin/main` is ahead by: somebody reading the log to decide whether
to pull was shown a log saying there is nothing to pull.

The scoped log is now one `git log` of both tips, ordered by git under
`--date-order`, so the branch and its upstream arrive already merged into one
sequence rather than stitched together afterwards. The commits the upstream has
and the branch does not are **dimmed as one piece** — the row, the dot, and the
whole line down to the commit they were built on — at the same quieter alpha a
merged branch is dimmed at in the refs tree. The `origin/…` chip stays at full
strength, because it is the thing explaining why the row is on the page at all.

The graph puts them where their parentage puts them: on the branch's own lane
where the upstream has simply moved ahead, on a lane of their own where the
histories diverged. The lane algorithm already did that; the commits only had to
be in its input.

**Paging kept the everything-log.** `loadMore()` dropped the `revision:`
argument, so the second page of `Log · main` was the log of the whole repository.
Fixed rather than inherited by the new loading path.

The unscoped log is untouched — it already sweeps `--all`.

## The refs tree sorts, and tags come newest first

Alphabetical order lies about versions: `v1.10` sorts before `v1.9`, so the tag
just cut was findable only by knowing its name. The odd part, found by reading
the code rather than by watching it: `GitBranches.list` has always asked git for
tags `--sort=-creatordate`, with a comment saying why — "an old tag is rarely
what anyone is looking for" — and `PathTree.sort` then re-sorted the rows by
display name before drawing them. The order was fetched on every refresh and
thrown away in the view.

TAGS now shows newest first. Right-clicking a section header offers the orders —
by creation date, by name — with a tick on the one in force; LOCAL and each
remote offer the same choice and keep by-name as their default. The choice is
remembered between sessions, per section kind, the way the log page remembers its
tree arrangement, and the filtered flat list obeys it too. Section headers had no
context menu at all before this: a right-click on `LOCAL`, `ORIGIN` or `TAGS`
fell through to the tree's catch-all.

The titlebar branch pill follows the LOCAL order, which keeps a requirement that
predates all of this — two lists of the same branches in one window do not get to
disagree about their order.

## Staging answers the click

Staging a file took one to five seconds to show. That is well past the point
where whether the double-click landed at all is in doubt, which is what the
report said, over a screenshot of fourteen changed files. None of the delay was
git's: `git add` and the porcelain status each cost tens of milliseconds in this
repository. It was five faults in the app's own sequence, traced and measured:

- The `.git` watcher called `Project.loadGit()`, which **discovered a new
  `GitRepository`** and threw away the ignore-rules fingerprint with it. So the
  walk the code itself calls "the expensive one" — `git status --ignored`, 0.82 s
  warm and 1.56 s cold over a 2.9 GB `build/` — reran after *every stage*, though
  its comment promises it is paid only when a `.gitignore` is saved. The watcher
  refreshes the existing actor in place now, and the promise is true.
- Nothing moved before a full status re-read and two from-scratch tree rebuilds.
  The rows switch sides on the command's own exit 0 now, and the status re-read
  that follows confirms or corrects. The status was always the authority and
  still is.
- A refresh arriving while a stage was in flight was **silently dropped** —
  `guard !isBusy`, no retry. That is the did-my-click-register case exactly. It
  is kept and run after now, the way the project navigator has always coalesced.
- The first click of a double-click rendered a diff on the main thread — 194 ms
  in the stall log — and the stage queued behind it. The render is deferred
  briefly and cancelled by the second click, so a double-click no longer pays for
  a diff nobody asked to read.
- Two rapid stages raced `index.lock`, and driving exactly that pair of clicks
  found one of them being lost with nothing said.

The cheap partial-refresh path now applies to repositories without submodules
instead of always answering `.everything`, and one rebuild's untracked-directory
listings are reused by the second rather than shelled out again. `StallWatch`
marks around the stage and the reload, so the next report of this shape names
itself in the log instead of counting as idle time.

## The commit page remembers, and keeps its Draft button

**Twenty messages back.** A history control beside the summary field opens the
repository's last twenty subjects; choosing one fills the summary and description
with that commit's full message. It fills fields and does nothing else — nothing
staged, nothing committed, both fields still editable, which is the rule drafting
already keeps. One `git log -20` when the menu opens, not per refresh.

**The Draft button stays visible when `claude` cannot be found.** It used to be
hidden outright, so on a machine where locating the executable fails the feature
did not exist to be asked about — which is how drafting a commit message with
Claude, specified since `commit-message-drafts` was written and shipped for
several versions, came to be requested as a missing feature. It is disabled now,
with a tooltip naming what is missing. A verb that vanishes teaches nobody what
the page can do.

## Changed lines in the editor gutter

A file open in the editor said nothing about what git thought of it. The gutter
could name who last touched each line, while the question asked far more often —
*which of these lines have I changed since HEAD?* — had no answer short of the
commit page or a terminal, and then mapping hunk numbers back to the window by
hand.

Open files now mark their changes in the gutter: a bar beside added and modified
lines, and a wedge on the boundary that deleted lines vanished from. Staged and
unstaged alike, so the marks answer "since HEAD" rather than "since the index".
They are anchored the way breakpoints are, so they stay on their lines while
somebody types, and they are swept once per repository change across every open
tab — commit, checkout, stage — as well as on save and reload.

Untracked, ignored and outside-a-repository files show nothing. A file that is
entirely new would be entirely coloured, which says nothing at all.

The mapping from hunks to line numbers lives in AbydosKit, computed from the diff
machinery that was already there, so it is tested without a window. One `git
diff` per file per save, reload or repository change — async, debounced, never
per keystroke.

## The hairline under both tab bars

Both tab bars painted their bottom hairline and then painted the trailing
controls' opaque backdrops over it, so the line stopped dead under the overflow
chevron and under the panel's controls. The editor bar draws the line after the
controls now; the panel strip's backdrop stops one point short.

## A window follows its shell

Following a terminal is the shell's own directory now. The waiting gate that
replaced foreground-reading in 0.10.0 traded brew's dragging for two new faults:
a running script deselected the project it was started from, and a pane holding a
Claude session never settled, so switching to its tab followed nowhere.

The shell's directory answers all three at once — a script never moves it, a
typed `cd` always does, and it is always there to read. For tmux that is the
`pane_pid`'s directory and **not** `pane_current_path`, which on this platform
follows the foreground process and so is the dragging fault a third time.

## Also

Four test suites were red for reasons that were the environment rather than the
app, and are not any more. The mermaid bake writes font stacks plain, because
WebKit began quoting computed `font-family` and the serialiser turned the quotes
into `&quot;`, six per label. The login `PATH` reader expands a tilde that a
single-quoted `export` leaves in an entry. A stopped Apple container runtime is
recognised by its own words rather than reading as a wrong verb. And the hook
tests address the pane rather than `window :0`, which a `tmux.conf` carrying
`base-index 1` does not have.

Ten changes were archived into `openspec/specs` alongside this release — the five
above and five that had been finished and waiting since 0.10.0 — so what they
decided is in the specs rather than only in the change directories. Five
capabilities are written down for the first time: `commit-message-history`,
`editor-change-marks`, `titlebar-capsule`, `pull-requests` and
`source-file-size`.
