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
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` says what the project now does
