## Context

What is on disk already, and what each is for:

    DiffView                 a unified diff drawn as coloured rows, virtualised, with
                             a side-by-side mode; selects lines to stage — and is at
                             the 1,100-line ceiling, with three extensions beside it
    DiffTextRun              the character selection over diff rows, a collaborator
                             that owns its state and holds no rows
    DiffHighlighter          both sides of a patch coloured by tree-sitter, off the
                             main thread (DiffPreparation)
    GitPatch                 a unified diff parsed far enough to stage parts of it
    WholeFileDiff            hunks spliced back into the file they came from
    PictureDiffView          two pictures side by side, three ways of looking
    GitBlob, GitHistory      a file at a commit; the commits that touched a path
    ChangesOutlineView       the tree of changed files, and its grouping by folder
    TreeRowView, TreeKeys    one tree behaviour for every tree (tree-behaviour)
    EditorDropView           a group's whole area accepts a drop
    Scripts/abydos           opens paths; inside the app's own terminal, over an
                             OSC 440 escape to the window the pane belongs to
    LaunchOptions            the driven-run verbs

Two constraints from the house that shape the rest. **Cost is a design
constraint**: a folder diff over a `node_modules` is a hundred thousand files,
and a file diff must open a lockfile as instantly as `DiffView` does — which is
why that view is hand-drawn and virtualised rather than an `NSTextView`. And
**no view code in AbydosKit**, so everything that decides — what is equal, what
aligns with what, which rows are hidden — is a value the tests can hold without
a window.

## Goals / Non-Goals

**Goals:**

- Any two files, any two folders, on disk or at a commit, compared on one page.
- A file diff that shows the whole of both files, walks change by change, and
  joins each change to its counterpart so the eye does not have to.
- A folder diff that is walkable at once and complete later, never the other
  way round.
- Copies between folders that are undoable from the Finder.
- The app usable as `git difftool`, for a file and for `--dir-diff`.
- Soft wrap in the diff.
- A live folder diff.

**Non-Goals:**

- Three-way merge. The shelf holds three; the diff is of two.
- Replacing `DiffView`. Staging is its job and it keeps it.

## Decisions

### 1. An in-process line diff, not `git diff --no-index`

`git diff --no-index -U999999 A B` would hand `GitPatch` a whole-file diff it
already parses, and it was the first thing tried on paper. Three things killed
it. A process per file pair, where a folder diff opens files one after another
and a history rail re-diffs on every click. The intraline marking the pictures
show — which characters of a changed line moved — is not in a unified diff at
all, so a second diff over the changed pairs is needed regardless, and once
there is one diff in the process there is no reason for two. And a blob at a
commit is already in memory through `GitBlob`; writing it to a temporary file
so git can read it back is the kind of cost this house writes down.

So `TextDiff` in `Sources/AbydosKit/Text/`: Myers over lines, linear space,
then the same algorithm over the characters of each changed pair of lines
where the pair is similar enough to be worth it — the usual test, more than
half the shorter line surviving, so that a line replaced wholesale is coloured
wholesale rather than as confetti. Lines are compared as `Substring`s of the
two texts so nothing is copied.

**Decided on 2,562 real edits: neither.** The measurement is below. git
implements all three algorithms, so what they do differently was asked of git
rather than written twice here, and they describe 97% of real edits
identically. Where they differ the metrics move by fractions of a percent, and
not consistently in one direction: histogram gives 1% fewer changes than Myers
on Swift and 0.3% *more* on Java. Nothing anybody would notice is on the table,
so plain Myers stays and `Myers.matches` remains the seam if that is ever
revisited.

The measurement was worth taking anyway, because it found two faults in our own
Myers that the algorithm question would have hidden — both fixed here, and both
about what the search is given rather than which search it is. See *What was
measured*.

### 2. The file diff is a new view sharing `DiffView`'s parts, not `DiffView`

`DiffView` is one file at its ceiling and three extensions, and its rows are a
patch's rows: hunk headers, then lines carrying `GitPatch.Line` and a
selection meaning of *stage this*. Two whole files have no hunks and nothing to
stage, and their rows are *pairs* — a left line and a right line, or one and a
gap — with a curve between the halves that a patch has no place to keep.
Widening `DiffView` to hold both was ruled out by its own header: it was split
into four files to stay under the limit, and this would be a fifth kind of
thing in it.

What is shared is exactly what the header says owns its state: `DiffTextRun`
for the character selection and what it copies, `DiffHighlighter` for colour,
and the virtualised drawing of one row from a font and a line height. The new
`FileCompareView` holds `[TextDiff.Row]` and draws them the same way, with the
curve drawn in the gutter between the halves from the top of a change on the
left to the top of its counterpart on the right, as a cubic through the middle
of the gutter — the same shape as the picture.

**Scrolling together** is one scroll view with one document view drawing both
halves, not two scroll views kept in step: two views kept in step is a frame
late on every wheel event, and the halves are rows of one alignment anyway.

**Wrapping** follows the editor's own switch, ⌥⌘Z, because the diff is read the
way the editor is read and one setting with two meanings is a setting nobody
can predict. With it on, a row is as tall as the taller of its halves, each
half's height being `WrapLayout`'s arithmetic — `ceil(columns / width)` on a
fixed-advance font, no typesetting — and the row tops are prefix-summed once
per layout so that a point maps to a row by binary search, as the editor's
do. The curve joins row tops as before; the change count does not see the
wrap at all. Ruled out: wrapping each half independently (the halves would
drift, and the alignment is the whole point) and a second setting for the
diff (see above).

### 3. A folder is compared by size, then by bytes, and never all at once

The row states the picture shows are *different*, *equal*, *unmatched*,
*ignored*. Unmatched and ignored are decided by the walk. Different and equal
need the contents, and reading every file of both trees before the page draws
is what makes a tool of this kind unusable on a real project.

So: the walk lists both trees, aligned by relative path, and every matched
file starts *unknown*. Sizes come free with the listing; different sizes are
*different* at once, which is most of them. Files of equal size are compared by
bytes on a background queue, in chunks, stopping at the first difference, and
the row moves to *equal* or *different* when its answer arrives. The title's
counts say how many are still unknown while any are. Answers are cached by
(path, size, mtime) on both sides so that reopening the page or applying a
copy re-reads only what changed.

Ruled out: hashing every file (reads everything, the thing being avoided);
`rsync -n` or `diff -rq` (a process, and one whose output is parsed by eye);
re-reading the whole of both trees on any event (the cost of the first open,
paid again for one saved file).

**The page stays live** through `FileSystemWatcher`, one stream per side on
disk, the same one the project tree uses. Its batches already say which
listings went stale, and that is the unit of work: the directories an event
names are listed again, rows are added, moved or removed under them, and a
matched file whose size and mtime are what the cache holds is not read. A
build writing thousands of files arrives as a coalesced batch and is one
re-list per directory, with the counts saying `listing…` again while it runs.
An *Apply*'s own writes arrive as events like any other and are what refreshes
the rows it touched, so there is no separate re-read after it. A tree at a
commit does not change and is not watched.

**Ignored** is the union of each side's `.gitignore` chain and the built-in
list the navigator already tints — build output, `.DS_Store`. The chain is
asked of `git check-ignore -v --stdin`, one process per side once the walk is
done, rather than matched here: `GitIgnore` turned out to *offer* patterns and
match none, and the syntax has a dozen corners that would each be a row greyed
on one side of the page and coloured in the navigator beside it. `-v` names
the file and line that decided each path, which is what the row's tip says. A
folder outside any repository ignores nothing this way. An ignored row is
shown greyed, not hidden, because the second-worst outcome of a folder diff is
not seeing the file that was different.

**Equal is hidden**, as the picture does, with the count in the title and a
switch to show them: a diff whose rows are mostly *same* is not a diff.

A folder at a commit is a `git ls-tree -r -l` — path, mode, size and blob id
in one process — and its files are `GitBlob`s read when a row is opened or
compared. Never `git archive` into a temporary directory: a tree of a hundred
megabytes would be unpacked to compare three files.

### 4. Copies are marked, then applied, and the Trash is the undo

The gutter between the trees offers, per row, *copy to B*, *copy to A* and
*delete*, and marking one does nothing on disk: the title counts *n items to
copy* and *Apply…* does them together after a sheet lists them. That is the
picture's shape and it is also the safe one — a copy that happens on click is a
copy that happened on a mis-click.

Overwriting or deleting first moves the existing file to the Trash with
`FileManager.trashItem`, the way `git-safety` leaves a backup ref, so every
apply is undone from the Finder's *Put Back*. Ruled out: a backup directory of
this app's own (another place to know about), and asking on every file (a sheet
per file is a sheet nobody reads by the third).

A side that is a commit cannot be written to and its gutter offers only copies
out of it. A file marked to copy whose comparison is still *unknown* is
applied all the same — the mark is the intent.

### 5. Sources, the shelf, and A and B

A `CompareSource` is one of `.file(URL)`, `.folder(URL)`, `.blob(repository,
commit, path)` or `.tree(repository, commit, path)`. The page holds a shelf of
them and two indices; the shelf is what dropping a third thing onto the page
adds to, and the chips are what choose. A file and a folder cannot be A and B
of each other; the chip is refused with the reason in a tip.

The history rail is the shelf's other feeder: `GitHistory` for the path, one
row per commit with the same A and B chips, and a click on the row's hash
opening the commit page `git-pages` already has. Choosing a commit as A makes
a `.blob` source and re-diffs; there is no separate "compare with previous"
because B-on-the-row-above is the same gesture.

### 6. Where the page opens, and the command line

An editor tab, like the diff tab and the log page, so it splits, tears off and
is remembered by `sessions` as those are. Its title is `a | b` with the counts
under it, which is what the picture's title bar shows and what the tab strip
already truncates well.

Entry points: two rows selected in the project tree and *Compare* in the
context menu; a file or folder dropped onto an open file (the `EditorDropView`
already takes drops over the text) — a file onto a file, a folder onto a
folder; *Compare ▸ With…* on a file, which asks with an open panel; and
`abydos-diff A B`.

`abydos-diff` is a shell script beside `abydos`, using the same OSC verb inside
the app's own terminal, with `compare` as the verb and two base64 paths.
Elsewhere `open -a` will not do — it opens files, and a running app is not
handed arguments — so the bundle registers a URL scheme, `abydos://compare?a=
…&b=…`, and the script opens that *by bundle identifier* (`open -b`), so a
build somebody is driving under a throwaway identifier never takes the
request; `bundle.sh` strips the scheme from such builds for the same reason it
strips the document types. `git difftool` with the alias in the README then
works for a file, and `--dir-diff` hands two temporary directories, which is
the folder diff.

**Answered for now, by a person.** `git difftool --dir-diff` copies edits back
from its temporary directory to the working tree only after the tool *exits*,
so `abydos-diff --wait` holds until Return is pressed and git does its copying
then. The app cannot yet tell the command that the tab was closed — that
would be an OSC back down the pty, or a notification the script waits on — and
until it can, Return is the signal; the README says so beside the alias.

### 7. Driving

`--compare <a> <b>` opens the page on a driven run, `--compare-steps` walks
it — next change, previous change, open row n, mark row n, show equal, filter
text — in the shape `--changes-steps` and `--hex` already use, and
`--screenshot` photographs it. The AbydosKit half — `TextDiff`,
`FolderComparison`, the ignore rules, the marks and what applying them does —
is tested without a window, under `TestDefaults.make()` and a scratch
directory, never a real one (item 0522).

## Risks / Trade-offs

- [A file diff of two multi-megabyte files is slow to compute] → Myers is
  O(ND); a minified bundle with one line is a single pair and the intraline
  pass over it is bounded — no intraline over a line longer than a few
  thousand characters, coloured whole instead. The diff runs off the main
  thread and the page says it is working, as `DiffPreparation` does.
- [The folder walk of a huge tree takes seconds before anything shows] → the
  walk is per directory, depth first, and rows appear as their directory is
  listed; the counts say *listing…* until it is done. Same shape as
  `git-changes-detail`'s untracked directory.
- [A copy applied to the wrong side] → the sheet before *Apply* lists every
  operation with an arrow, and the Trash holds what was there.
- [Two `.gitignore` chains disagree about a path] → ignored if either says so,
  and the row's tip names which.
- [A wrapped diff has rows of varying height, and a scroll position has to
  find its row] → the row tops are prefix-summed once per layout and searched
  by bisection, which is `WrapLayout`'s own shape and costs O(log rows) per
  frame; the sums are rebuilt when the width or the switch changes and not
  otherwise.
- [A watcher storm — a build writing into one side — re-lists the same
  directory many times] → `FileSystemWatcher` batches, one re-list per named
  directory per batch, and the byte comparisons for that directory are
  cancelled and restarted rather than queued twice.
- [A strip of the page paints over the rest of it] → since macOS 14 a view
  does not clip to its bounds, and `dirtyRect` reaches across the whole page:
  every hand-drawn view here fills `bounds`, and the page clips. Found by
  driving — the folder diff came out as an empty page, the trees painted over
  in the editor's own colour.
- [The curve between the halves is drawn for every change and costs per
  frame] → only the changes whose rows intersect the visible rect are drawn,
  which is the same bound the rows have.
- [`git difftool --dir-diff` copy-back] → open question above; until it is
  answered the README says so beside the alias.

## What was measured, 2026-09-10

**The subject is a revision pair** — a file as one commit found it and as that
commit left it. The corpus `Scripts/corpus.sh` clones cannot supply one: those
clones are `--depth 1`, so they hold exactly one version of everything and a
diff is of two. Any repository with history is full of pairs instead. Two
corpora, both real edits by the people who wrote them: 1,927 pairs from this
repository, and 635 Java pairs from one Eclipse repository cloned with 300
commits of history — Java because it is the shape the silly match is most
likely in, a language where a great many lines are a closing brace and nothing
else.

`TextDiffCorpusTests` is the harness, under `SCALE=1`, and it prints the table
below. Three numbers, none of them a duration: **changes**, the maximal runs of
non-equal rows that the reader walks; **changed lines**, removals and additions
together, where a shorter diff of the same edit is a better description of it;
and **lone anchors**, an unchanged *trivial* line with a change on either side
of it — a brace, a blank, a comment terminator. That last one is the silly
match named in this design, made countable: the diff claimed the brace closing
one function is the brace closing another and split the edit around it.

This repository, 1,927 pairs. git's three describe 58 of them differently
(3.0%):

| | changes | changed lines | lone anchors | seconds |
| --- | --- | --- | --- | --- |
| `TextDiff` | 9,167 | **167,834** | 797 | 11.1 |
| git myers | 8,612 | 168,383 | 283 | 64.6 |
| git patience | 8,557 | 167,957 | 254 | 18.6 |
| git histogram | 8,525 | 168,087 | 257 | 18.7 |

Java, 635 pairs. git's three describe 24 of them differently (3.8%):

| | changes | changed lines | lone anchors | seconds |
| --- | --- | --- | --- | --- |
| `TextDiff` | 3,556 | **20,993** | 416 | 1.2 |
| git myers | 3,379 | 21,061 | 179 | 11.9 |
| git patience | 3,390 | 21,047 | 194 | 6.1 |
| git histogram | 3,390 | 21,049 | 211 | 6.1 |

**What the algorithm question is worth: nothing.** Read down git's own three
rows. The seconds are process spawns and say nothing about the algorithms.

**What the measurement found instead, both fixed.**

*Lines that can match nothing are taken out before the search.* A line
appearing nowhere on the other side can be in no common subsequence, so
removing it changes none of them — an exact reduction, not a heuristic, and
what git's xdiff does before it runs Myers at all. Without it a large rewrite
presents the bounded search with an edit distance far larger than the number of
lines that could ever pair up, and the search gives up and splits at a point it
has not reasoned about. Our diff was longer than git's on **18 of 1,927** pairs
before, worst 9,932 changed lines against git's 3,640 on a file of ten
thousand; with the reduction, four.

*And then the bound can afford to be generous.* It was four times the root of
the region with a floor of 256, chosen when it was the only thing standing
between the diff and the square of a hundred thousand lines. The reduction is
that now, so what remains inside the bound is a region whose lines do mostly
pair up, where giving up early costs a visibly worse diff and saves nothing.
Sixteen times the root with a floor of a thousand: longer than git on **one**
pair of 1,927, by a single line, and the corpus total fell to 167,834 — below
git's own — for the same 11.1 seconds.

**One gap left, and it is not the algorithm.** Our lone anchors are two to
three times git's — 797 against 254 to 283, 416 against 179 to 211 — and git's
three are all alike, so no change of algorithm can close it. What git has and
we do not is the post-pass: `xdl_change_compact` slides a run of changed lines
up or down where the alignment is equally valid, and the indent heuristic
picks which of those equally valid placements reads best. It moves no line in
or out of the diff, which is why our changed-line total is already the shorter
one; it decides where a run is said to begin. That is a separate piece of work
with a measurement already written for it, and it is the one worth doing next.

## Open Questions

- How `abydos-diff --wait` learns the tab closed, rather than being told by
  a person pressing Return.
- Whether a compare tab is restored by `sessions` when a side was a temporary
  directory that is gone — probably a tab that says so, as a `FileNotice` does.
