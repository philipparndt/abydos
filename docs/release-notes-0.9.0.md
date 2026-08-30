# Abydos 0.9.0

A version of its own, for one reason: a checkout of two or three hundred
repositories is now a thing this program can hold open and work in. The rest of
the release is the editor and the debugger catching up on things that were
reported — find and replace, breakpoints that belong to the project, a commit
page that reads at the size it is given — and two faults found while looking at
something else.

## A superproject is one working copy

A refactoring across a microservice estate is done in a superproject that holds
two or three hundred repositories as submodules. Until now this program had
never heard of one. `grep -rin submodule` over the git integration returned
nothing, and the design that built the current git tool had said so on purpose.

What that cost was not a missing feature but a slow one already running.
`git status` in a superproject recurses into every submodule, serially, inside
one process — and this app runs it on **every filesystem event**, which during a
build is dozens a minute. Measured on a real estate of 200 services:

| what was asked | seconds |
| --- | --- |
| what the app used to run | **1.57** |
| the superproject alone, `--ignore-submodules=dirty` | **0.09** |
| `git submodule status`, the obvious replacement | **5.31** |
| all 200 asked at once, twelve concurrent | **0.45** |
| the inventory, one `ls-files --stage` | **0.01** |

So one question became two. The superproject is asked with
`--ignore-submodules=dirty`, which is not a weaker answer — it still reports
every gitlink whose recorded commit has moved, which is the one thing only the
superproject knows — and each submodule is asked separately, in parallel, under
a ceiling. That ceiling is measured rather than chosen: twelve concurrent read
200 in 0.45 s and twenty-four read them in 0.46 s, and unbounded is three
hundred git processes against ten cores while a build is running.

**After the first read, nothing is swept.** Every submodule's git directory
lives under the superproject's own, so two watchers cover three hundred
repositories rather than six hundred, and a write inside one service re-reads
that service alone — 0.01 s against 0.45 s for the estate.

**Every verb is aimed at the repository that owns its path.** `git add` resolves
a pathspec against the repository it runs in, so a submodule's file staged in
the superproject staged nothing at all. The verbs were never wrong; they were
being handed the wrong root.

### Submodules ⇧⌘M

One page that answers "where is this refactoring": a row per service with what
changed in it, the branch it is on, how far that is from its remote, whether the
superproject records it somewhere else, and its pull request. Ordered by what
needs something — conflicted, changed, ahead, moved, then the quiet ones —
because three hundred alphabetical rows of which four matter is a page nobody
reads twice.

It fills in passes and never lies in between. The inventory is two git calls, so
every row is on screen saying `reading…` before any status exists; a row without
an answer never says clean, which would be a sentence about this program dressed
as one about the code.

### The rest of the estate

**The changes pane draws it and stages in the right place.** `src/main/java` is a
real path in every one of two hundred services, so a submodule is a row above its
folders and staging it runs `git add` there. A submodule that has moved *and* has
uncommitted work is one row saying both, in that order.

**A gitlink conflict has three ways out.** It is the one conflict no merge tool
opens: what is in conflict is which commit of another repository this one points
at, so the resolution is a commit. Take either side, or merge inside the
submodule and take what that leaves — which is what git's own hint tells you to
do when it gives up. The row says what lies between the two sides in commits,
because "conflicted" alone leaves you to run `git log` before you can choose.

**A commit across repositories reports itself per repository and never claims to
be atomic.** Nothing can make two hundred commits one transaction, and the
rollback that would pretend otherwise is `git reset --hard` in repositories
somebody may already have fetched. A failure at the fourth of six leaves five
commits standing and says which; the run is resumable. Pushing goes the same way,
submodules first, because a superproject pushed first records gitlinks nobody
else can fetch.

**Pull requests across the estate are one set**, keyed by its branch: one title
and body, a pull request per repository with commits on that branch, and a
sentence saying how many are failing, awaiting review, approved or merged. Its
state is read from the forge every time and never stored — a local record of
numbers goes stale the moment somebody merges from the web.

**The refs tree holds the submodules** as a section that shows what needs
something and counts the rest, and the repository row says how many it holds.

**The safety net covers a whole estate.** One question for the operation, every
repository backed up before any file is discarded, and one report naming each
repository and its backup ref. Asking two hundred times is asking nobody. The
"do not ask again" checkbox has also been drawn on that dialog since it was
written and never stored anything; it works now, and it is keyed per repository,
because an answer given while looking at one service is not a decision about two
hundred.

**Nested submodules and linked worktrees** work, and turned out to be one fact: a
submodule's git directory is always its parent's plus `modules/<name>`. The
worktree half was a silent failure rather than a missing feature — a worktree's
git directory sits outside its work tree, so nothing there was ever attributed,
and the pull request review flow creates worktrees.

## Find, and what the selection looks like elsewhere

**Find and replace**, with highlights that follow the text as it is edited.

**The other places the selected text appears no longer look like the selection.**
They were coloured to stay under the find band, which is the wrong axis: find's
matches win while find is showing, and the two never share a page.

## The debugger

**Breakpoints belong to the project, not the window.** A checkout that had never
had a debugger pointed at it was holding four breakpoints from unrelated
projects, found by reading the JSON because nothing in the window could show
them.

**There is a list of them.** A breakpoint was drawn in the gutter of its own file
and nowhere else, so six across four files could only be checked by opening four
files — and the verb that silences all but one was reachable only by
right-clicking one of them in a gutter.

## The commit page

**The diff gets the room.** A page a few hundred points tall was showing four
lines of diff — one hunk header, two context lines and the pair being changed —
under an empty description box. The message area was a fixed 224 points across
the whole width; it is two rows now, under the diff, and the description is
behind a chevron until it is asked for.

**It no longer takes the window.** It maximised the editor on the way in because
it was unreadable small, and that reason is gone.

## The project tree

**Ignored files no longer flash as though they were part of the project.** The
greying-out came from `git status --ignored`, which walks the whole work tree
with git's untracked cache switched off — 0.41 s against 0.03 s for the same
status without it, on a checkout whose build directory is 6.4 GB and 31,350
files — and it runs *after* the tree has been coloured, so the first paint could
not have known. The tree now asks `git check-ignore` about the rows it is about
to draw, which costs the number of rows rather than the size of the project:
0.01 s, whether it is asked about forty paths or three hundred. The full sweep
still follows, because it is the one that notices a folder that has *stopped*
being ignored.

That took two goes. The first shipped doing nothing: the tree's row list includes
the node everything hangs off, whose path is the empty string, and git refuses a
whole batch over it — `fatal: empty string is not a valid pathspec` — so one
unaskable path discarded the other three hundred and twenty-seven. It was
reported still flickering, which is the only reason it was found.

**And a selected file still says whether git is ignoring it.** Selecting a row
sent it to one colour whatever its state, so an ignored file looked exactly like
a tracked one for as long as it was selected — clicking a file to find out about
it removed the answer.

## Two faults found while looking at something else

**Doc comments were being drawn in two colours.** In a block of ten `///` lines,
five were highlighted as documentation and five as ordinary comments with nothing
to tell them apart. It is arithmetic: tree-sitter node offsets were halved and
doubled back, which is lossless only for even offsets, so a comment starting at
an odd byte had its text handed to the pattern one byte early and the `^///`
anchor failed. About half of any file's doc comments land on each side. Every
`#match?` in every grammar was affected the same way; doc comments are only where
it was easy to see.

**The delete dialog says what each branch costs.** It asked you to lose commits
without saying how many, and listed the branches as a paragraph that wrapped each
name in the middle of itself. The branches are rows now, with the refs tree's own
glyphs and a count each, and the sentence leads with the total.

**The repository row pushes the branch it is describing.** Every word on that row
is about the branch the work tree is on, and its button pushed whatever was
*selected* in the tree below it — so a row saying "not published" about the
checked-out branch published a different one. Reported after it sent `main`
instead. It names nothing now and lets git push `HEAD`, which is the only
spelling that cannot be out of step with the work tree; pushing some other branch
from its own row still works, because doing that without checking it out is
deliberate.

**A 3MF opens instead of failing to build.** Pressing `o` on a file that is
already a `.3mf` took the output's name from the input, so the command asked
go3mf to combine the file with itself and reported the refusal — "at least 2
files required for combining" — as a build failure. There is nothing to build:
the file is handed to whatever opens a 3MF. Fixed in gostl, which this release
takes at 0.23.3.


## Under the suite

Nothing here changes the app, and it is the reason the rest can be trusted.
Seven tests asserted a duration, or waited, on a number somebody had chosen
after watching that test fail — which is what this project's `MachineLoad`,
`Stopwatch` and `Patience` were written to end. Three bounded a wall clock with
no load guard, one read a process's `isRunning` on the line after asking it to
terminate, one slept four seconds where it could have watched, and three waits
were simply too short.

`TimingBoundTests` now reads the test sources and fails on an absolute ceiling
over a measured duration that has no load guard, the way `NamedSuiteTests`
already guards the preferences rule. Flaky tests are worse than no tests, and a
rule that only lives in a comment is one the next person writes past.
