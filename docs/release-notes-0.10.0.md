# Abydos 0.10.0

A release about the git pane, and nearly all of it reported by somebody looking
at the thing while using it. The pattern is the same one over and over: the pane
knew the answer and was not saying it, or was offering a control that did
nothing, or was saying a true sentence about the wrong object.

## The strip above the tree, while git is stopped

A stopped merge used to say this:

    Merging 0b7d23b0 Publishing with no remote asks for one, in a dialog th…
    3 files conflicted
    [Continue] [Abort]
    [Files] [◧] [Prompt]

Three faults in one screenshot. The headline named a commit — a short hash and
the whole subject of somebody else's commit, truncated — with the one thing you
want, which branch is coming in, not in it. The only actionable fact was a
number, and the quietest thing in the strip. And `Abort`, which throws work
away, was full size directly under a `Continue` that was not, greyed for a
reason kept in a tooltip.

It now reads `Merging publish-offers-a-remote into main`, and **the files are
rows**. Click one to open it. Right-click for the two sides — named by branch,
never "ours" and "theirs" — or for `Mark Resolved`. Each row ticks green and
strikes through as it clears, the line under the headline counts `2 of 3
resolved`, and `Continue` lights when the last one turns, so the disabled button
no longer needs a sentence explaining itself.

**Never "ours" and "theirs" on screen.** Stage 2 is `--ours` in both a merge and
a rebase and they are opposite halves: rebasing replays your commits onto
somebody else's, so the branch you are on arrives as `--theirs`. A menu item
saying "Use Ours" during a rebase throws away the wrong half and nothing in the
wording says so.

**Git forgets, so the pane remembers twice.** A path stops being unmerged the
moment it is staged, so a list built from what is unmerged *now* shrinks instead
of ticking. The pane holds the set for one stop and also reads what git wrote
under `# Conflicts:` in `.git/MERGE_MSG`, so a merge reopened tomorrow still
counts the files already dealt with.

The manual path is the one this is for: open the file, edit the markers away,
press `Mark Resolved`. A file whose markers have gone but which is not staged
says `edited` in amber — the one state with no other signal on screen. It does
not refuse to stage a file that still has markers: a file can legitimately
contain those characters, and this repository has one that documents them.

## Fetching, and knowing when you last did

There was no way to fetch while ahead. The repository row draws one verb chosen
from its state — fetch when level, pull when behind, push when ahead — so a
repository sitting `1 ahead` offered `Push` and nothing else, and the glyph
beside it re-read the repository locally. Finding out whether anybody had pushed
meant a terminal.

Which is worse than a missing button, because the state is stale too: `1 ahead`
is a claim about a tracking ref, and a tracking ref is a copy of what the remote
said the last time somebody asked. The one verb the row draws is chosen from a
reading that can be days old, and the only thing that refreshes it was the thing
there was no way to reach.

So the glyph fetches, where there is a remote to fetch from — the pane already
re-reads on every filesystem event, so a manual press was only ever for
something that happened *elsewhere*, and the largest elsewhere is the remote.
The row has a right-click with all four verbs on it, and says when the remote
was last asked, first in that menu: `.git/FETCH_HEAD` is one `stat` and no
subprocess.

## Remote branches

`git branch --merged` lists local branches only, which is why the pane could
mark a finished local branch and had nothing to say about the remote copy of the
same work. `-r` is the whole difference — and the target is the *remote's*
default, not this machine's. `origin/x` inside the local `main` is not the same
claim as `origin/x` inside `origin/main`: a commit merged locally and not pushed
moves one ref and not the other, and it is the second that decides whether
deleting the branch loses anything.

They can be deleted where they are, too. That is a push, and the only one this
app makes that is not somebody publishing their own work, so it says where the
branch is going from and says the one reassuring thing that is true: pushing the
branch again puts it back, if the commits are still somewhere.

## Looking into a stash

A stash was a commit nobody could read. The tree opened one to a list of file
names and stopped there — no diff, no counts, nothing that said whether the
thing was worth keeping — so the way to find out what a week-old stash held was
to apply it over a clean working copy and look, which is the one move somebody
with work in progress cannot make.

`Review…` opens it as a page in the commit page's shape: the files on the left,
the diff of the selected one beside them, the verbs along the bottom. Read-only,
because a stash has already happened. Untracked files come with it — git keeps
them in a third parent, and they are exactly the half somebody has forgotten
they had.

The working copy can also be put aside from its own row now, with a dialog that
asks for a name and whether untracked files go too. **They do by default, which
is not git's default**: `git stash` without `--include-untracked` leaves new
files where they are, so a work tree meant to be clean still has them in it —
and the file you have just written is both the one you are most likely putting
aside and the one still untracked.

## The refs tree

- **A slash is always a folder.** Folding merged a folder holding exactly one
  branch into it, so `origin/renovate/configure` was one row reading its whole
  path while two `feature/*` branches got a `feature` folder: the tree changed
  character with the count.
- **`origin` and `Tags` start shut.** They are somebody else's account of things
  — every branch anybody has pushed, every release there has ever been — and
  unrolled they are the bulk of the pane.
- **The current branch is bold**, as well as green.
- **The counts are a column**, on the row's trailing edge where the ahead and
  behind counts and the merged ticks already were.
- The working copy says `no changes` rather than `clean`. One word in the place
  a verb would go reads as one, with `Review 3 changes…` at the other end of the
  same row.

## Two dialogs that could not be used

**The recreate dialog was clipped, and the clipped part was the affordance.** It
has been a picker over every ref in the repository since it was written; its
accessory was 280 points inside an alert whose content is 272, so the combo box
overhung the dialog and the one piece outside the edge was the chevron. It read
as a plain text box, because that is what a combo box with its chevron cut off
looks like.

**Publishing a branch with no remote now asks for one**, in a dialog that fits a
URL rather than breaking `git@github.com:…` across three lines.

## Following a terminal

A window follows its terminal into a Subversion or Mercurial working copy now,
and into `.abydos` — this app's own record that somebody opened a folder as a
project. A folder in none of those is shown without being a project: the tree,
the search and the index point at it, nothing is written into it, and it is not
recorded as a recent.

**Following into such a folder is a setting of its own, off.** Following between
projects moves the window when somebody goes to another piece of work, and a
working copy is what says the walk is over. A folder has no such edge: with it
on, `~/Downloads` is somewhere to follow to and every `cd` anywhere is a move.

**And the window only moves when you move.** The directory was read off whatever
was in the foreground, which while a command runs is the command — so `brew`,
which changes directory several times over one install, dragged the window
through every one of them. Nothing typed is lost by the fix: `cd` is a builtin,
so the shell forks nothing and never leaves the foreground to do one.

## Fixes

- **A path git had to quote is put back before it is used.** A stash of a change
  under `farbe-ständer` listed its files as `"farbe-st\303\244nder/…"` and
  showed *No textual changes.* beside every one of them — the escaped spelling
  is a name no file has, so the diff was asked for by a path git had never heard
  of. It reached the log page and the pull request page too.
- **The commit page's diff can stage the lines it offers to stage.** Right-click
  a selection there and it offered "Stage Selected Lines (15)", enabled, and
  pressing it did nothing whatsoever: the menu is built for any diff that is not
  read-only, and only the editor's diff had ever been told what to do with it.
- **The repository row pushes the branch it is describing**, not whatever was
  selected in the tree below it.
- **A long branch no longer hides the project it belongs to.** A toolbar that
  cannot fit an item does not shrink it — it moves it to the overflow menu — so
  the one thing that says which project this is was the first to disappear.
- **Ignored files are grey on the first paint**, and stay grey when selected.
- **The log page no longer takes the window.** The commit page stopped doing
  that in 0.9.0 for the same reason: the panel's height and the tree's width are
  somebody's own arrangement, chosen for what they were doing a minute ago.
- **A fold marker in the log is drawn in the colour of what it folds**, not of
  the row it sits on — a blue mainline was offering a blue button that hides a
  red branch.
- **The warning sweep actually recompiles what it reports on.** `make warnings`
  said "No warnings" and exited 0 on a tree that had two, which is the failure
  the script was written to prevent, inside the script itself.

## Under it

57 files changed, 5,486 insertions. 3,899 tests, and `make warnings` clean —
including the sweep that had stopped sweeping.
