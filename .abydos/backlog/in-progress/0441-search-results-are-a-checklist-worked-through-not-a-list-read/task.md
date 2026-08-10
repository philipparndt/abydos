# 441. Search results are a checklist to work through, not a list to read

A search across a project answers with more than fits on a screen, and going
through it is a job of work: open one, decide, move on. There is nothing that
holds *which ones have been dealt with*, so the list looks the same after an
hour as it did at the start, and the only place the progress is kept is in
somebody's head.

So: several rows can be selected at once, and dismissed. Dismissing does not
touch the file — it means **"I have looked at this one"**, and the result list
becomes something that gets shorter as the work gets done.

## The hazard to design around first

**One pane away, on the same list-shaped thing, that gesture destroys.** In the
project tree ⌘⌫ moves a file to the trash. Here the same idea means "tick it
off". Two meanings for one word, in one window, and one of them touches the
disk — and the search list is full of file names, so nothing about the row says
which meaning is in force.

That is the thing to get right before any of the rest. It probably means the word
is not "delete" in the interface however it is described in a backlog entry, and
it may mean the key is not ⌫. A dismissal that reads as a deletion is worse than
no dismissal at all, because somebody will avoid using it.

## What the rows are

`SearchPane` holds a flat `[Row]` of `.file(FileSearchResult)` and
`.match(FileSearchResult, SearchMatch)` — a file heading with its matching lines
under it. So "select several and dismiss" has to answer what a mixed selection
means:

- Dismissing a **file** row takes its matches with it. Nothing else makes sense:
  the heading is the file.
- Dismissing a **match** leaves the file if it still has matches that are not
  dismissed, and takes the heading with it when the last one goes — otherwise
  the list keeps headings for files with nothing under them.

The table also has to allow multiple selection, which it does not today.

## Worth deciding

**Struck through, or gone.** A checklist that empties gives the satisfying
shortening list and loses the record of what was done; one that greys and strikes
through keeps the record and keeps the scrolling. The word "checklist" suggests
the second, and the sentence "the way the search result can be a check list"
suggests ticks rather than disappearance — but it moves rows under the cursor
either way and should be chosen deliberately.

**Whether it survives the search being run again.** This is the question that
decides whether the feature is worth anything. Working through 200 matches takes
long enough that the search will be re-run — a file gets edited, the tree
reloads, somebody adjusts the term by one character. If dismissals are forgotten
each time, the feature only helps within one uninterrupted sitting. If they are
remembered, then remembered *against what* — the search term, the file and line,
the file and the matched text? A line number goes stale the moment the file is
edited above it, which is exactly what somebody working through a result list is
doing.

**Undo**, which is 0442 and is cheap here for once: nothing was destroyed, so
putting a row back is putting a row back. It is worth making sure the two land in
a way that agrees rather than inventing a second private undo for this list.

**Whether "dismissed" is per search or per project.** Two searches for different
things over the same file are different questions, and having answered one is not
having answered the other.

## Steps

- [x] Settle the word on screen and the key, and write down why neither is the
      tree's
- [x] A `SearchChecklist` in AbydosKit: what a mark is keyed on, and marking,
      unmarking and counting
- [x] Tests for the key: a mark survives lines being added above it, two
      identical lines do not tick each other, another question has its own marks
- [x] The table takes several rows at once, and a click that is building a
      selection no longer opens a file
- [x] ␣ marks the selection done and marks it back; ↓ from the field reaches the
      list; ⏎ opens what is selected
- [x] Done rows are struck through and dimmed, and a file heading follows the
      matches under it
- [x] A "hide done" toggle, so the list can also be the one that empties
- [x] ⌘Z in the pane takes the last marking back, through the same responder
      chain the tree's undo uses
- [x] Marks survive the search being re-run under the same question
- [x] A `--search-steps` harness verb, so the pane can be driven from the
      command line
- [x] Seen in the running app, not only in tests
- [x] Write down here what was ruled out on the way
- [x] `spec/search.md` says what the project now does

## What it came to

The word on screen is **done** — "Mark as Done", "Mark as Not Done", and a
status line that ends "· 3 done". The key is **␣**. Rows are struck through and
greyed where they stand, with a tick at the right-hand end, and the file heading
counts them: `3/6` while it is part way, a tick when it is finished. `✓` in the
controls hides everything already done, which is the other list — the one that
empties — on request rather than by default.

A mark is remembered against the file, the trimmed text of the matched line, and
which of the identical lines in that file it is. Marks are held per *question*
— the term plus the three option buttons — for the life of the window.

## Ruled out

**⌫ and ⌘⌫ for the gesture.** ⌘⌫ trashes a file in the tree one pane away, on a
list that looks very like this one. Neither is bound here, and both were checked
in the running app to do nothing at all: pressing ⌘⌫ over a selected match
changed no mark and moved no file. "Does something different" would have been
worse than "does nothing" — a key that is destructive in one list and harmless
in the next is a key nobody presses in either.

**"Dismiss", "Delete", "Remove", "Clear".** "Dismiss" is the word the entry
uses and it is the wrong one on screen: it sits exactly halfway between putting
a thing aside and getting rid of it, which is the ambiguity being designed
against. "Mark as Done" cannot be read as touching the disk.

**Rows disappearing when they are marked, as the default.** That is the
satisfying shortening list, and it has two faults that matter more. Everything
below the marked row moves up under the pointer, so the next ␣ — the same key,
pressed in a rhythm — lands on a row nobody has read. And a row that is gone
cannot be unticked, which makes ⌘Z the only way back from a mistake instead of
the second way. So: struck through by default, hidden on a toggle.

**A line number as the key.** This is the one the entry warned about and it is
worse than it looks: the person working through a result list is the person
editing the files, so the numbers go stale under their own hands. Checked in
the app rather than argued: a file was edited from outside the window while its
matches were on screen, the search re-run, and the mark stayed on the same
`return needle` — now line 7 rather than 6 — and not on the identical one
further down.

**The matched text on its own.** A file with twenty `return nil` in it would
tick all twenty at once. Hence the occurrence count, which counts only among
lines whose text is identical and is therefore unmoved by every edit that does
not add another copy of that same line above the marked one. That last case
does still get it wrong — the tick lands on the first of the two identical lines
— and it is not fixed. Two lines that are character-for-character identical
under the same query are about as indistinguishable as this list can make them.

**Marking a file in its own right.** The heading's state is derived: done when
every match under it is. Storing it separately would mean a re-run that turns up
one new match in a finished file kept the file hidden, and a new match is a new
thing to look at.

**Marks per project rather than per question.** A line holding both `TODO` and
`FIXME` would arrive already ticked under the second search. Checked: a list
ticked under `needle`, re-searched for `return`, comes back with nothing marked,
and going back to `needle` finds the marks where they were left. The options are
part of the question for the same reason, and nothing is thrown away when they
change, so an accidental click on `Aa` costs a second click and not an
afternoon.

**Writing the marks to disk.** Not done, deliberately, and this is the limit
worth knowing: quit the app and the ticks are gone. A mark means "I have looked
at this one", and how long that stays true is a question nobody has asked yet —
a mark restored a week later, against a file rewritten twice since, would be a
quiet lie in exactly the direction that matters, which is a row saying "looked
at" when nobody looked. Within the window it survives everything a session
throws at it, which is what the entry asked for.

**A second private undo.** The pane has an `UndoManager` of its own answered by
the table through `undo:`, which is the same shape as the tree's file undo and
for the same reason: `undo:` goes down the responder chain and stops at the
first object that answers, so a stack per pane is what keeps the ticks and the
files apart. Checked both ways in the running app — with the keyboard in the
list, `SearchResultsTable` answers; with it in the search field, `NSWindow` does
and no mark is touched.

It does depart from the tree in one place: this one has a **redo**. The tree has
none because redoing a copy means keeping the source it came from, which is a
promise it cannot make. Nothing is destroyed here in either direction, so
registering the inverse from inside the handler is free, and ⇧⌘Z puts the ticks
back.

**⏎ leaving the keyboard in the editor.** It did, at first, and it made the
checklist unusable from the keyboard: the next ␣ typed a space into the file. ⏎
now shows the match and gives the keyboard straight back to the list. A click
and a double-click are unchanged and still hand over, because somebody who
clicked a line of code means to be in it.

**A checkbox column down the left.** There is no room: the match cell already
right-aligns the line number into the first 34 points, and a tick column would
have indented every row for the sake of a mark most rows do not carry. The tick
went to the right-hand end instead, where the file heading's match count already
lives — so that edge of the row is now where state is, on headings and matches
alike.

## What is checked, and what is only looked at

`SearchChecklist` has nine tests, and they cover the part that decides whether
the feature is worth anything: what a mark survives. Everything else — the
selection, the key, the striking through, the undo, the hiding — is in
`AbydosApp`, which the suite cannot reach.

So a `--search-steps` verb was added to the launch harness, and the evidence for
the pane is its transcripts: `rows` prints every row with the done state the
pane believes it has, which is the half a screenshot cannot show. A grey line
with a tick beside it looks the same whether the pane is right or wrong about
it. What was seen with the eyes as well is one rendering of the pane over this
repository, with three of six matches in one file struck through, the heading
reading `3/6` and the status line `13 in 4 files · 3 done`.

Not checked by anything: the context menu, which a window rendering cannot
photograph, and the ␣ key arriving from a real keyboard rather than a
synthesised event through the table's own `keyDown`.
