# Abydos 0.8.1

Fifteen commits in a day, and no single one of them is worth a version of its
own — which is what a point release is for. Most of them are the git tool
becoming something you can finish a piece of work in rather than a picture of
one: several branches deleted at once, a rebase carried to its end, a head that
is not on a branch saying where it is. There is a fourth palette in here too,
because it was ready and a theme is not a reason to hold everything else back.

## Branches, and being finished with them

**Several at once.** Selecting five merged branches and deleting them one dialog
at a time is five presses of a button whose sentence is the same every time,
which is how nobody reads it. One dialog now, written from what was found rather
than from what was asked, so the two cases read differently: *already on main —
nothing would be lost*, or *not on main — these would lose commits*, with the
names under each. Destructive styling only where something would actually be
lost; a merged branch is a name, and painting that red is the boy who cried wolf.

**A branch a worktree has checked out offers to take the worktree with it.** Git
refuses those outright — `cannot delete branch 'x' used by worktree at …` — and
all the pane could do with that was repeat it afterwards in git's words. What
somebody wants at that moment is nearly always to be rid of both, and the
directory is the part taking up the disk: the one that made the house rules grow
a section was 4.9 GB of checkout and build output on a disk at 99% full. So the
worktree is a second control with what it would free measured beside it, ticked
by default only where nothing in it would be lost — git's own rule, which counts
untracked files, because a worktree's build output is untracked and so is the
file somebody has not committed yet.

**Whether anything would be lost is decided by ancestry**, `merge-base
--is-ancestor` against the branch you are standing on, and the delete follows
from that answer. `git branch -d` answers a different question and had the last
word: it refuses a branch sitting ahead of its own *stale* upstream — "not fully
merged", meaning `origin/<branch>` is behind — even when every commit on it is
already on `main`. A branch listed under "nothing would be lost" would then quietly
stay where it was while the rest of the selection went.

**The rows say what is being worked on.** A delete is not instant: removing an
11 GiB worktree takes seconds and every branch is a git of its own, and a list
that looks exactly as it did is indistinguishable from a press that never
landed. Each row spins until git has answered for it, and a worktree that would
not go stops its row there rather than leaving it turning over work nobody is
doing.

*Copy Name* copies every branch that is selected, since the reason to select
several at once is nearly always to paste the list somewhere. Checkout, merge
and delete are each about one branch and stay that way.

## A rebase can be finished from inside the app

There was no way to carry one on. The banner appeared while files were
conflicted and vanished the moment the last one was resolved — which is the
middle of a rebase, not the end of one. Nothing here ran `git rebase --continue`,
so the flow stopped where it most needed to go on, and the commit page, which is
where somebody naturally goes next, makes an ordinary commit, which is the wrong
move there.

The strip is about the *operation* now, for as long as one is in progress, and
carries the three verbs that end one: Continue, Skip and Abort. It says what git
has written down about where it is — the position, the branch, the commit being
rebased onto, the message of the commit in hand — as a bar and a line, and it is
as tall as what it is actually showing rather than a guess that left a hole above
a merge.

`--continue` exits 1 both when it refuses to move and when it moves, applies the
commit and stops on the *next* conflict. The first is a mistake to report and the
second is a rebase working exactly as it should; the position git keeps tells
them apart.

## Where the head is when it is not on a branch

A detached head used to draw nothing at all: no tick in the tree, and a titlebar
pill that returned before it wrote anything. The two moments somebody most needs
telling — a commit checked out directly, and a rebase stopped part-way — were the
two the window was quietest about. It now says `detached at 8d9ac24b`, with what
git has stopped in the middle of beside it, in the pill, on the repository row
and as a row of its own at the top of Local.

## Reading the repository again

A fetch, a rebase or a branch deleted in another window happens somewhere the
watcher is not looking. There is a refresh glyph on the repository row now,
beside the traffic button, with a spinner while it reads — several git calls on a
large repository, and a button with no feedback reads as a button that did
nothing, so somebody presses it again. It no longer sits flush against *Fetch*,
where the two read as one wide control with a line down the middle.

## Space opens Quick Look

For the kinds the system genuinely previews — an image, a video, a PDF — Space is
what opens them everywhere else on this machine, and here it did a provisional
open: a notice with a Quick Look button on it, two presses to reach what one
press reaches in the Finder. Everything else keeps the provisional open, which is
what Space is for in a tree of source files. The panel is fed the selection, so
four rows with two images in them is a panel of two the arrow keys walk through.

## Gray

A fourth palette: grey with the blue let go of. Nearly every dark theme carries a
blue cast in every surface, which is what makes a window of them look like the
same window. This one takes the hue out of the chrome — a hair warm, because an
exactly equal grey reads as faintly green on a display — so the surfaces say
nothing at all and the syntax does the talking. Light and dark, as every scheme
here is, and its own sixteen-colour terminal palette so the terminal is not left
wearing somebody else's.

## Inverse video, when no colours were named

`ESC[7m` on its own did nothing. Swapping a cell's two colours moved `.default`
into the background slot, and both renderers then asked for that slot in a way
that turned it straight back into the default background — so an inverse cell
with no colours set was indistinguishable from a plain one by the time anything
could draw it. Prompts, `less`, `man` and tmux's own decorations all ask for
reverse video exactly that way, because the point of it is to swap whatever is
there.

## Claude Code's hooks, from Settings

Uninstalling another tool could take the whole `hooks` block out of
`~/.claude/settings.json`, and with it the entries that make Claude Code report
what a session is doing. Nothing in the app said so, and putting them back needed
a command in a terminal. There is a switch for it now, which reads the file
rather than a preference — those entries live somewhere this app does not own,
and a switch showing "on" over an empty file is worse than no switch.

The repair itself was broken. It recognised its own hook by a name the binary
stopped having when the project was renamed, so installing twice left two entries
per event, an app that moved left the old entry beside the new one, and `remove`
removed nothing at all.
