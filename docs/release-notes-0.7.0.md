# Abydos 0.7.0

Forty-five commits. Two of them are cases of something coming back empty
without saying so, one is the largest single piece of housekeeping this
repository has had, and the rest of the release is the git tool being rebuilt
around one idea: a verb belongs on the row that draws the thing it acts on.

## The git tool has no header

The strip above the branch tree cost **58 points** — an inset, a search field, a
half-inset, a row of two buttons, a half-inset — in a pane 300 points wide whose
whole job is a list. A row of that tree is 24 points, so the chrome was two and
a half branches nobody could see. What it bought was poor: a permanent field for
a filter used occasionally, and the *second* branch filter in the window at
that; a full bezel for `New Branch…`; and no way at all to reach the thing done
most often here.

It is gone. The pane is one list from its top edge, and everything the header
held went to the row it was about.

**The repository is the first row, and it does not scroll away.** It says how
far the branch you are on is from its upstream — `2 behind · 1 ahead`, `level`,
`upstream gone` — and it is the button: fetch when level, pull when behind, push
when ahead. It says nothing else, because the titlebar a few points above it
already names the project and the branch, and a row repeating them was a glyph
and two words already on screen. It stays put while the rest of the tree
scrolls, which is the one thing a header was doing that a row does not get for
free: how far you are from the remote is state, and state that scrolls behind
forty branches is state nobody reads.

**Committing is on the working copy row, and it is not called `Commit…`.** That
reads as *commit now, after a confirmation*, and nothing is committed by
pressing it — it opens the view where hunks are chosen and a message written.
The row reads `Review 2 changes…`, which names what happens next, and the
context menu and `⇧⌘K` say the same words so the three ways in cannot drift.

**The filter is on `⌘F`**, opening over the list the way the editor's find bar
does, closing on `⎋` and when you empty it. `LOCAL` carries a `+` for a new
branch. Every verb a row offers is reachable with `⌘⏎` as well as the pointer —
these panes were fixed a few commits ago not to be mouse-only, and a verb that
only appears under the pointer would have undone that.

## What a branch row tells you now

The end of every branch row is a single right-aligned column, and what sits in
it is either news or a standing fact:

    main ✓            ↑2 ↓1     two to push, one to pull
    feature/api          ↑3 ☁︎↑  three commits of its own, never published
    old-thing              ☁︎✗   its remote branch was deleted
    shipped                 ✓    already merged — the row is dimmed too

**A merged branch is dimmed rather than moved or hidden.** Where a branch sits
in the list is how it is found, so a branch that moves when it merges is one you
hunt for, and one that disappears vanishes at the moment it becomes safe to
delete. The tick is not dimmed with the rest of the row — it is the reason the
row is grey, and fading the answer along with the question leaves nothing on it
saying why. The branch you are standing on never dims, whatever git says about
it.

**`main` is pinned under the branch you are on**, which is the order the branch
pill in the titlebar has always used. Two lists of the same branches in one
window disagreeing about their order meant that learning where `main` was in one
of them taught you nothing.

**A branch nobody else has seen now says how much work is on it.** Its upstream
counts are nought and nought — which is exactly what a branch *in step* with a
remote reads — so a branch of your own said nothing about itself. It is measured
against the default branch instead.

Only the ahead half is drawn, and that is deliberate. `↑` and `↓` are this
pane's remote vocabulary — waiting to go up, waiting to come down — so `↓1557`
against `main` borrowed the second to say something else entirely: not *there
are commits to pull* but *main has moved on, and you may want to rebase*. It
read as the first, which on a row where every other arrow means that is the only
way it can read. The figure is in the tooltip instead, in words, naming what it
is measured against.

**And a branch can become a pull request.** `Publish and Open Pull Request…` on
a branch the host does not have, `Open Pull Request…` on one it does — the two
steps as one verb each, because having to know that the push comes first is what
makes this the part of the job people leave the app to do. The publish happens
first and the page is not opened if it fails. `Open on GitHub` is now offered
only where the forge actually has the ref, rather than on every local branch: a
page for a branch the host has never heard of is a 404, which is a worse answer
than not offering.

**`backup/` keeps its folder however few refs are under it**, and the folder
finally carries the verb the specification has given it since it was written:
deleting the entries older than a chosen age, with the count of what each age
would take shown *before* you choose. A backup ref is the only copy of what it
holds, so *everything older than a month* cannot be weighed without knowing
whether that means four refs or forty.

**The change counts line up.** In the commit view, a folder's `+69 −16` sat a
tally's width further left than the `+25 −3` of the file beneath it, so reading
down a nested tree the plus signs stepped in and out by a digit at every level.
They are columns now.

## Two things that came back empty

**An unsteady click no longer empties the clipboard.** tmux copies on
selection. This app forwards the click that activates a window straight through
to the program, so that clicking from elsewhere onto a tmux pane selects it in
one gesture rather than two. Together, a hand that moved two points between
press and release sent tmux a drag — it entered copy mode, selected nothing, and
on release copied that nothing over the system clipboard. The next paste was
empty, and nothing on screen said why.

The pointer now gets a whole terminal cell in each direction before the program
hears about a drag at all. Waiting costs the selection nothing, which is what
makes a whole cell safe rather than merely generous: the program was already
told where the button went down and anchors there, so this decides only *when* a
selection starts, never where.

**A busy machine no longer drops a subprocess's output.** The pipe readers ran
on `DispatchQueue.global`, which overcommits to about sixty-four threads per
quality of service — and every one of these reads blocks its thread until end of
file. Run enough commands at once and the readers for the newest were still
*queued* when the two-second deadline passed, so the wait gave up on a read that
had never begun.

The caller then got exit code 0 and an empty string from a command that had
worked. Nothing reported an error, because nothing had failed: git ran, git
succeeded, and its answer never got read. Callers took that as "no changes",
"no stashes", "no files in that commit". It surfaced as flaky tests —
49, 21 and 24 failures across three parallel runs, every one a value that should
have been read coming back empty — but a test suite is not the only thing that
runs git under load. The readers have a thread apiece now; those suites went to
four runs, all passing, in 4.4 seconds.

## Keyboard, focus and windows

**The git trees can be walked with the arrows.** Neither the commit's file tree
on the log page nor the Changes tree could be, and clicking one did not mark its
tab as focused. Both had the same cause: the panes are plain containers, and the
keyboard came to rest on *them* — focus was somewhere, and nothing answered. A
page now opens with its list ready to be walked, `←` and `→` shut and open
folders, and both trees say when the keyboard arrives.

**The log and commit pages open with the window.** Both exist to be read, and a
third of a window is not what they are for. Which means there has to be a
visible way back, so there is a button for it — at the trailing edge of the tab
strip, where the other things that act on the editor live. The icon is the
state: arrows apart to take the window, arrows together to give it back.
`⇧⌘⏎` and a double-click on an already-open tab do the same.

**A terminal selection stops where the row's text does.** It used to highlight
the full width of the grid whatever the row said — eighty columns of nothing
beside a two-word prompt. What got *copied* was always right, which is why this
lasted so long: nothing was incorrect, only unreadable. `⌥` now makes a
rectangular selection.

**The Claude Sessions section keeps its place while a session works.** The
selection used to jump and vanish, and levels you had open never showed anything
new.

## Files, sizes and the tree

**A binary file is called binary, whatever its size.** A 400 MB `.mov` was told
"This file is 405,7 MB — too large to open as text", which is a statement about
text made about something that was never text. The size check ran before the
binary check, so every large binary got the wrong half of the truth. A binary
file now says how big it is and offers to be looked at — including video, which
is the obvious thing to do with a video.

**Every size in the window is MiB.** The tool window's memory column was the
last place dividing by 1024 and labelling the answer `MB`, sitting beside a file
notice saying `MiB` about identical arithmetic. One function decides every size
on screen now, with seven tests on the boundaries a second implementation would
get wrong.

**An ignored folder is grey, even inside an untracked one** — it was drawn in
the colour of uncommitted work, which is the one thing that tint exists to say.
**An untracked folder is a folder** with its contents under it, rather than one
row with a `?` and nothing beneath. **A commit's files arrange by folder** on
the log page and say how much of each changed.

**A breakpoint outlives the session it was set for**, which is most of what
makes it a breakpoint rather than a command.

## Under the hood

`MainWindowController.swift` went from **13,030 lines to 927**. The window is
now its collaborators, its init, and the delegate conformances AppKit resolves
against it; everything else moved out to the thing it was about — the titlebar,
the sidebar, the results, the run cluster, debugging, the editor's server
actions. Nothing here is a behaviour change, and the release is better tested
for it: a good deal of the driven checking added along the way is what caught
the bugs above.

There is also a ceiling on how long a source file may be, recorded per file so
that twenty-seven existing offenders do not fail the build on day one. A listed
file may shrink freely and may not grow silently;
`MainWindowController.swift` is the first entry to leave the list.

## Known

`git-refs-tree`'s unpublished-branch count uses `%(ahead-behind:)`, which
arrived in git 2.41. On an older git the listing falls back to the format
without it rather than showing no branches — that fallback is by construction
and has not been tested against an old git.
