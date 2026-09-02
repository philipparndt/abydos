# Abydos 0.11.0

This was going to be 0.10.1. Three commits landed the day after 0.10.0 and no
single one of them was worth a version of its own, which is what 0.8.1's notes
say a point release is for — the git pane again, and nearly every item in it
named after a direct report from somebody looking at the pane while using it.

Then two things arrived that are worth one, and they are the same kind of thing:
a file that has always opened as a *notice about itself* now opens as what it
is. A video plays in a tab. A `.env` opens with its values already unreadable,
because the screen it is on might be being shared. Both are the editor answering
the question somebody actually had, and neither of them fits under a point
release.

The concealment then kept going for two more days on its own reports — a YAML
block scalar whose key was in the clear under a covered `pk: |`, and a revealed
file that stayed revealed in a background window — and two more doorways were
found to be missing rather than absent: comparing a file from the row it is on,
and blame from the gutter it draws in. Then a project learnt to come back with
the commit message somebody was halfway through typing, a draft learnt the format
most repositories' tooling actually reads, a pane got the pager every other
terminal has, and a terminal stopped losing a row every time the window got
wider.

And then the release stopped in notarisation, and the version was held open
while somebody used the app and said what was wrong with it. That last part is
most of what is below: a day of reports, each one a person looking at a pane and
naming what it did. The zoom turned out to reach almost nothing that was not
painted by hand, the git tree had four different ways of throwing a selection
away, and a folded merge left the lanes of the branch it hid running down the
graph with nothing above them.

Twenty-nine commits, 255 files.

## Secrets in a dotenv file are not on the screen

Screens get shared — a call, a review, a demo — and the `.env` that was open a
minute earlier, or that gets opened *during* the call to check a name, puts its
API keys in front of everyone watching. The reflex of closing the file comes
after the leak, and rotating a key costs an afternoon.

macOS gives an app no reliable signal that its window is being captured, so the
protection cannot wait for one. The values are unreadable **by default** rather
than on cue.

In dotenv-shaped files — `.env`, `.env.*`, `*.env` — and in `*.dec`, the shape a
SOPS-style decrypt leaves behind, everything after the separator is erased to the
row's edge in the row's own background, with one fixed twelve-column pill marking
where the value began. Nothing about the value survives, **its length included**:
a cover the width of the secret tells a room how long the secret is, and a
twelve-column pill in front of a forty-character key tells them nothing. Keys,
`export` prefixes, comments and empty values stay readable, because the reason to
open the file is usually to read those.

**The reveal is file-wide and deliberate.** A lock sits on the left of the status
bar — "Secrets hidden" shut, "Secrets shown" open — and `View ▸ Reveal Secrets`
is the same switch's other handle. Clicking a cover reveals nothing, and answers
with a notice naming the lock instead. That is a decision taken against the
proposal: per-value click-to-reveal was built and then reviewed out, on the
argument that a click is exactly what a presenter does absentmindedly, on the
very screen being watched. Arrow keys and find lift nothing either, which a
driven script proves rather than asserts.

**The cover is a rendering, not a transformation.** Offsets, the caret, undo,
find and copy all see the real text — copying a value copies the value, which is
a deliberate act that puts nothing on a screen. Typing into a covered value stays
covered, the way a password field takes input; the screen is precisely where the
new key must not appear.

**A block scalar is covered whole.** This was reported with a screenshot that
made the point better than words could: a `secrets.yaml.dec` with a covered
`pk: |` and the RSA private key it introduces drawn in the clear on the indented
lines below it. Per-line classification cannot see a YAML block scalar, because
its value lives on the lines *after* the indicator. The roles are computed over
the whole file now — a value that is exactly an indicator (`|`, `>`, and the
`|-`, `|+`, `>2` modifier forms; a value merely *starting* with a pipe is a
value) opens a block, every deeper-indented or blank line after it is block
content, and the first line back at the key's indent closes it and is a line
again. A mapping's children are keys and stay readable. Block-content rows erase
whole with a pill each, so a redacted key reads as a redaction rather than as the
file ending early.

**A revealed file covers itself again.** Five minutes with no key, click, scroll
or edit and the covers go back on by themselves, the lock in the status bar
shutting with them — a document left unlocked in a background window is exactly
the leak the covers exist for, and it is the case nobody remembers to close.
Scrolling counts as touching the file: reading a long one is interaction, and
covers marching in over somebody mid-read is how a feature gets switched off for
good. The cost is a timestamp, not a timer per keystroke — one deferred check,
re-armed for whatever is left of the five minutes.

The whole thing is *Conceal secrets* in the editor settings, on by default, and
it reaches already-open tabs the moment it flips. The detection and the value
ranges live in AbydosKit, so which part of `export FOO="bar" # note` is the
secret is decided somewhere testable without a window.

## A video plays in a tab

Opening a video opened a notice: this file is binary, here is a hex viewer, here
is Quick Look. The notice's own comment conceded the point — "the obvious thing
to do with a video is watch it" — and then handed the watching to a floating
panel that covers the editor, belongs to no tab, and closes on a keypress. A
picture opens as the picture, a PDF as the document, a mesh rendered; the video
was the last rendered form still being handed off.

An `.mp4`, `.mov` or `.m4v` now opens as AVKit's player in a tab shaped like a
picture's: no document, no dirty state, closed like any other, with the system's
own transport controls.

**It never speaks uninvited.** It opens paused on its first frame, because an
editor tab is often opened mid-meeting and autoplay puts sound into it. Switching
away pauses — a hidden tab with a voice in it is a haunted window — and coming
back does *not* resume; only somebody pressing play does. The tab stays off the
Now Playing centre for the same reason.

Only the containers AVFoundation decodes natively are claimed. A `.webm` keeps
the notice and its Quick Look button, because a player spinning over a black
rectangle is worse than a notice that is honest about it. That negative is in the
change's screenshots, driven, beside the positive one.

## The zoom reaches every control

⌘+ and ⌘- have always reached everything this app paints for itself, because
those read the theme as they draw and so re-read it on the next repaint. They
reached almost nothing else. Seven reports on 2026-09-01, with screenshots, and
they were one fault: the log page's search field and its scope control at system
size beside rows that had grown; the commit page's `Stage`, `Draft`, `Commit`
and `Push` keeping their bezel while the words inside them grew; the whole
pull-request header not moving at all; the commit row's height read once, so at
a larger zoom the short hash on its second line was **clipped by the row**; and
the commit page's detail area still at the presentation size after presentation
mode was switched off.

`DrawnButton` already carried the diagnosis and the measurement: on macOS 27 a
system bezel is 20 points tall at `.small` and 28 at `.large` whatever font is
inside it, so raising `controlSize` moves the wall from 1× to about 1.4× and
then stops. What it did not carry was any reach — two callers, against about
seventy bare `NSButton`s.

**The app already had three right answers and no shared one.** `DrawnButton` for
the missing-server strip, `PillButton` for the titlebar, and `RowAction` for the
git tree's `Review 3 changes…` — which was pointed at during the work as "the
one that works at all zoom levels", and does, for the reason all three do: every
dimension is read from the theme *where it is used*, so there is nothing stored
to go stale. Three correct implementations of one idea, in three files, is the
argument for a library rather than against it. What is new is only that the
answer is shared, and that one registry sees a control asked again when the zoom
moves under it — because the seven reports were seven panes that forgot, and a
mechanism whose correctness depends on remembering is what was being replaced.

Four panes moved onto it: the log page, the commit page, the pull-request review
page and the pull-request list. Along the way the same fault turned up in five
more places, none of them a control:

- **The commit row's height is derived from the two lines it draws**, through
  arithmetic tested at all nine zoom steps, rather than the `40` that was right
  once. The line is drawn at the offset that arithmetic gives, so what is
  measured and what is drawn cannot disagree — which is how they came to.
- **The diff view heard the zoom and threw it away.** Its handler opened by
  asking whether either of the two *diff* preferences had moved; a zoom matched
  neither and returned, leaving the font at the size it was read at. That is why
  a diff scaled only when it was closed and opened again.
- **`ChangesPane.applyThemeChange` existed, did the right thing, and nothing
  ever called it.** The sidebar hid that by rebuilding the pane wholesale; the
  commit page in a tab is never rebuilt, so it never followed at all.
- **A placeholder keeps the font it was assigned with.** `NSTextField` renders
  it from the font in force at the moment it is set, so the commit page's
  `Summary` stayed small while everything around it grew.
- **The editor's change mark had no gap from the line numbers** — and worse than
  none. The mark's position scaled and the number's inset was a fixed five
  points, so the two closed on each other as the zoom rose: touching at about
  1.2×, and the bar drawn over the digits above that.

And the project tree kept its dark background in a light window. Its colours
were copied when the view was built, and the method that re-applies its row
height and its indentation had never been given them — while the header directly
above it fills as it draws, and followed. One pane, half light and half dark, in
one screenshot.

## The tree keeps hold of the selection

Expanding a folder with → left it open with nothing selected. Staging a file
emptied the selection. Both were reported within an hour of each other, and they
were **the same fault**: an outline view's `reloadData()` clears its selection,
and the commit page reloads from four places, three of them asynchronous — so
the rebuild carefully put the selection back and something landed a moment later
and wiped it.

It took four goes, and each fix uncovered the next. The untracked-directory
listing reloading when it came back. Three staging paths of which only two
recorded where the selection should land. `isRestoring` cleared on the next
*line* while `NSTableView` posts its selection change on the next *turn*, so the
pane's own restore read as a click — and what that does is clear the other list,
which is why the selection blinked onto the right row and vanished. And finally
the one that was still doing it: the `--numstat` line counts come back and
reload, and that code knew a reload throws the *expansion* away, put the
expansion back, and had never heard of the selection.

Where the selection goes is the tree's other half. Staging a row is a deletion
from the list it was in, so it lands on the nearest surviving row above — the
sibling, or the parent when there is no sibling, which in an outline view are
the same movement. And when the file was the only one in its folder the folder
empties too, so there is nothing above at all: it falls to the row below
instead.

**The tree also draws the app's selection now.** The changes tree had no row
view of its own, so AppKit painted its system-blue band inside a window that
draws a rounded, inset pill everywhere else. The four trees people use all day
share one row view. The commit list, the debugger's variables, the breakpoint
list and the value popup keep the full-bleed band, which is right for a run of
records and wrong for a hierarchy, where a band swallows the indentation that
says what is inside what.

## A folded merge takes its lanes with it

Folding a merge hid its commits and left the branch's lanes running down every
row below, starting nowhere — "the green and purple lanes start in the nowhere".
The graph was laid out over every commit and the rows were filtered afterwards,
so a surviving row kept lanes it had been given while the hidden commits were
still there.

The obvious fix is worse than the bug, which is worth recording. Filtering the
commits and dropping the merge's hidden parent removes the lanes — and stops the
merge being a merge: with one parent it has nothing to fold, so it loses its fold
marker and **can never be opened again**. So the whole history goes to the
layout and it is told which of it is off screen. It keeps counting what a merge
brought in, which is a fact about the history rather than about what is drawn,
and opens no lane for a commit nobody will see.

## The tree marks a changed file

The project tree said a file had changed by colouring its name and in no other
way, which is only legible against the names beside it: a run of untracked files
reads as a tree of green text, and one modified file among forty is a word in a
slightly different colour. A row with a version-control state now carries a dot
at its trailing edge in that state's colour, files and folders alike — and a
folder's state is already the roll-up of what is under it, which is what makes
the mark worth having on a **collapsed** one. Nothing for unmodified or ignored:
in a project with a build directory those rows outnumber everything else, and a
mark on nearly every row is furniture.

## The git pane always offers Fetch

The repository row draws one verb chosen from its state — `Fetch` when level,
`Pull` when behind, `Push` when ahead — so `Fetch` was the one verb that
disappeared exactly when somebody wanted it: a branch one commit ahead offered
`Push` and no way at all to ask whether anybody else had pushed.

There was a glyph beside it that already fetched, and said so only in a tooltip.
A tooltip is not a label, so it was reported as a missing button while it sat on
the row being pressed for something else — the same shape as a hidden `Draft`
button being reported as a missing feature two releases ago. It is a control
that says `Fetch`, shown whenever there is a remote.

**Removed**: the glyph's local re-read where there is no remote. The pane's own
watcher already re-reads on every filesystem event, and `Read the Repository
Again` is on the row's context menu, where it already was.

## The commit page's row settles

Seven controls at four heights with two kinds of emphasis. The chevron, the
clock and `Draft` are quiet now — no edge, no fill, the pill back under the
pointer — because they help write the message rather than doing anything to the
repository; `Commit` and `Push` are the only bordered controls, and everything
takes the summary field's height. Neither action is filled: the accent pill was
a white block that landed on `Push`, the one action that is not about the
message being written. ⌘⏎ still follows whichever the page is for.

And the diff arrives on the click. Selecting a change waited out the
double-click interval before asking git — half a second on every click and every
arrow key — to stop a second click's stage queueing behind a render that held
the main thread. A double-click is nearly always on the row that is already
selected, which changes no selection and never reached the wait; and the render
is off the main thread now, with a generation counter dropping the answer for a
row nobody is looking at any more.

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

## A drafted message is a Conventional Commit

The Draft button asked Claude for a message in *this* repository's voice: the
prompt carried the last twenty subjects, and the code beside it said in as many
words that this repository does not write `fix: update handler`. That is one
house's style shipped as everybody's default. Most repositories that want a
message drafted want the format their tooling reads — changelogs, releases and
version bumps all key off Conventional Commits — and a draft in prose has to be
rewritten by hand before it can be committed at all.

The summary is now asked for as v1.0.0 states it: `<type>[optional scope][!]:
<description>`, the type one of feat, fix, build, chore, ci, docs, style,
refactor, perf or test, the scope a noun in parentheses naming a part of the
codebase, and a breaking change marked either with `!` before the colon or an
uppercase `BREAKING CHANGE:` footer. A toggle on the Git settings page turns it
off, on by default — and with it off the prompt is **byte for byte** what it was,
which a test asserts rather than assumes. A setting that "mostly" restores the
old behaviour would leave this repository's own drafts quietly worse, and nobody
would connect that to a release.

The twenty subjects still go either way, demoted to vocabulary when the format is
on. Twenty narrative subjects and an instruction to write `feat(scope):` are
contradictory instructions and the examples usually win — but the scope is the
half a diff alone cannot settle, and `fix(navigator):` against
`fix(ProjectNavigatorViewController):` is the difference between a scope and a
file name.

**What comes back is never rewritten into the format.** Prepending a type is
classifying somebody's change on their behalf, and a wrong classification reads
as deliberate and lands in a changelog under the wrong heading.
`ConventionalCommit` reads a summary and never writes one; the fields stay
editable, which is the recovery.

## Comparing a file, from the row it is on

Both destinations already existed, and neither was reachable from the file it is
about. A file row's menu gains a **Compare** submenu: *Against Last Commit*
opens the HEAD diff as the diff tab — staged and unstaged edits in one answer,
not two — and *History…* opens the log page scoped to that file with the *This
File* segment lit.

On a file-scoped log, a commit's own menu gains **Compare with Working Copy**:
`git diff <hash> -- <path>`, which is the other question a version answers — not
what changed *in* it, but how far *now* is from then. It is offered only while
the log is path-scoped, because on the whole log that question spans every file
and the menu item would be lying about what it opens.

The submenu obeys the row it is on: an untracked file has *Against Last Commit*
disabled and no *History…* at all, and a folder or the repository root has no
submenu. In the kit, `diffToWorkingCopy` joins `diffAgainstHead`, with live tests
proving that an older commit's diff carries a later commit's edit and that a
matching working copy diffs to nothing.

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

## Blame, from the gutter's own menu

Right-clicking the line numbers opened the *text* area's menu — Go to Definition,
Paste — so blame mode, which has been behind ⌥⌘B all along, was reported as a
missing feature. The gutter answers with a menu of its own now: *Show Blame* or
*Hide Blame*, the title saying which state the gutter is in, and the action
walking the responder chain to the one toggle that ⌥⌘B and the View menu already
share. The text area's menu is byte for byte what it was. Blame mode also gets
its first account in the specs, having shipped for months without one.

## A project comes back with its message and its pages

Switching to another project and back lost two things somebody was in the middle
of, and neither loss was an accident.

The session filtered git pages out of its capture, on the argument that "a path
like `/ideai/page/launch` is nothing to reopen" — true of the synthetic URL, and
false of the page, which is a view over a repository with a scope and a
selection. And the commit message lived in two private text fields and nowhere
else, so a rebuilt pane came back empty.

**A commit message is the most expensive text in the app to lose.** It is written
once, from a diff that has just been read, and typing it again means reading the
diff again. So both halves travel, summary and description, the description being
the one that says why.

There is a second door onto the same loss, and the code had already confessed to
it in a comment: reading the repository finishes a second or two after a window
opens, and when it lands on a different work tree the sidebar tool is rebuilt —
taking, in the comment's own words, "the commit message half typed into the
pane". The message is therefore re-applied wherever a pane is *built* rather than
once after the switch, and only into an empty field: somebody who has started
typing has said something more recent than the file has.

The pages come back through the openers a click uses, after the repository is
readable — every one of them refuses while the project's git is unread, and would
have dropped the restore in silence. They are idempotent, so a restore racing a
click cannot produce two log pages. A stash page is remembered **by commit, not
by index**: `stash@{0}` is a different commit after one `git stash push`, and a
page reopened by index would come back on somebody else's work. A stash that has
since been popped opens nothing.

Both fields are additive optional values in `ProjectSession`, absent from every
session written before them, so an older session file loses nothing by not having
them.

## Dragging a divider with a picture open took the app down

Three identical reports in two minutes against 0.10.0. The drag's nested event
loop flushes layout; `ImageFileView.layout()` resized its document view from
inside that flush; the scroll view re-tiled and pulled its between-scrollers
corner out of the hierarchy; and this macOS treats a hierarchy mutation
mid-flush as an illegal layout-engine modification — an `NSException` out of
`_postWindowNeedsUpdateConstraints`, caught by `NSApplication`
`_crashOnException`, which is a crash with somebody's window in it.

The picture's geometry is applied *between* passes now, never inside one:
`layout()` schedules one coalesced `layoutPicture()` on the main queue, which
drains in the event-tracking mode too, so the picture still follows the divider
live — one turn behind, with the layout engine at rest. The direct callers, a
zoom and a fit and the image arriving, stay synchronous; none of them runs inside
a flush.

## The terminal keeps its height when the window gets wider

Dragging the window's right edge out took a row off the terminal per resize
notification — dozens in a single drag — until the panel hit its 160 pt floor and
the height somebody had set was gone. Reported with two screenshots of the same
window at two widths.

Nothing couples width to height on purpose: the panel's height is points rather
than a fraction, and the terminal's cell size comes from font metrics alone. It
was two mistakes standing together, neither of them visible on its own.

**The snap was not a fixed point.** `setPosition(_:ofDividerAt:)` leaves the
second subview `total - p - dividerThickness` tall, and the position was computed
as `total - wanted` with no thickness term. So the panel came out a point short,
its usable height a point short of whole rows, and the *next* remainder was
nearly a whole row for the next pass to take off again. The comment beside it
said "it converges in one step: the second pass finds nothing left over and
stops", which is exactly what did not happen — and the test asserted the
off-by-one as an expectation.

**And a width-only resize asked the question at all.** `NSSplitView` posts
`didResizeSubviews` for any frame change, and the handler filtered on which split
view sent it and never on whether the height had moved.

Both are fixed, along with the three other places computing a divider position as
`total - height` — putting the panel away and back, making room for the editor,
maximising it — and the harness's own copy, which had been placing captures a
point out. The test asserts the property now rather than the arithmetic: apply
the answer, recompute the state it produces, and there is nothing left to round.

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

## A pane has a pager

`git log` in a pane printed everything and returned to the prompt, where every
other terminal on the machine opens a pager without being asked. One line did it:
`PAGER` was defaulted to `cat`, to stop a pager hanging a pane waiting for a
keypress. That was true of a terminal that could not run a full-screen program.
This one runs vim, htop, Claude's own full-screen UI and tmux, and a pager is
that same class of program.

The `??` it was written with looked like deference and was not. The dictionary
starts from the *app's* environment, and a `PAGER` exported from a profile is set
by the shell inside the pane, long after the fork — so the app's value was what
git saw, and every tool a pane started inherited it, not just `git log`. It was
reported by somebody who found it by unsetting the variable by hand and asking
whether it was deliberate.

**Deleting the line is not the whole fix**, which is the part worth knowing. tmux
copies the environment it was started with into its global environment and hands
that to every window it makes for the rest of the server's life. The server on
this machine has been up since 28 August, so with the line gone a pane on it
still reported `PAGER=[cat]` and `git log` still printed everything — measured,
not assumed. So the app takes its own footprint back at launch:
`show-environment -g PAGER`, and only if the answer is exactly `cat`,
`set-environment -g -u PAGER`. Nobody chooses `cat` deliberately, a session's
environment is not ours to edit beyond what we put there, and no server running
is nothing to clean rather than a failure.

## Also

**A tooltip could take the app with it.** `addToolTip` retains no owner, and a
bridged `NSString` handed to it as one was freed before the tooltip timer got
around to asking it anything — a `SIGSEGV` inside `NSToolTipManager`, on the
first day the secrets lock had a tooltip. The view is the owner now, for the lock
and for the server chip in the status bar, which had been getting away with the
same mistake for some time.

**Three classes moved out of the commit page to make room**, which is the size
ledger doing its job rather than getting in the way. It refused a change twice,
and the second time it was right about something real: the machinery for
re-taking a pane's heights had been written inside `ChangesPane`, and it is
generic — every pane that copies a height out of the theme has the same fault.
Moved to the library, it left the pane eleven lines smaller than it started.

**Four test suites were red for reasons that were the environment rather than the
app**, and are not any more. The mermaid bake writes font stacks plain, because
WebKit began quoting computed `font-family` and the serialiser turned the quotes
into `&quot;`, six per label. The login `PATH` reader expands a tilde that a
single-quoted `export` leaves in an entry. A stopped Apple container runtime is
recognised by its own words rather than reading as a wrong verb. And the hook
tests address the pane rather than `window :0`, which a `tmux.conf` carrying
`base-index 1` does not have.

**Fourteen changes were archived into `openspec/specs`** over this release — ten
on the 31st and the four features above on the 1st — so what they decided lives
in the specs rather than only in the change directories. Six capabilities are
written down for the first time: `secret-concealment`, `commit-message-history`,
`editor-change-marks`, `titlebar-capsule`, `pull-requests` and
`source-file-size`. `previews` gains the video player, `editor` gains the
gutter's own menu and the redaction band's place in its painting order — over
every band, under the caret — and `git-pages` and `project-view` take one compare
doorway each.

**Ten changes are not archived, and that is the honest state of this release.**
Four were finished before the version was held open —
`a-draft-is-a-conventional-commit`, `a-pane-has-a-pager`,
`a-project-comes-back-as-it-was-left` and `the-terminal-keeps-its-height`,
carrying deltas to `commit-message-drafts`, `terminal`, `sessions` and
`git-pages`. Their work is here; only the move into the specs is outstanding.

Five more were written during the day of reports above, and are complete in the
app and short of their driven proofs: `the-zoom-reaches-every-control` (26 tasks
of 31, the five outstanding being captures), `the-git-pane-always-offers-fetch`
(4 of 8), `one-tree-behaviour-everywhere` (12 of 19 — every report fixed, the
extraction across the other three trees still to do),
`a-collapsed-merge-takes-its-lanes-with-it` (done) and
`the-tree-marks-changed-files` (3 of 4).

One is filed and not started. `the-backlog-pane-stays-under-the-tab-strip` is
the backlog's toolbar drawn over the panel's tab strip, reported with a
screenshot and with the word *sometimes* in it — which is what an ordering fault
looks like from outside. Its first task is reproducing it before anything is
written, because the panel's constraints say it cannot happen, and a plausible
fix for an intermittent fault will appear to work.

`a-java-edit-reaches-the-running-jvm` stays where it is, at 24 tasks of 31. It is
somebody else's work and it is not finished.
