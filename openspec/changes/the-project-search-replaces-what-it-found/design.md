## Context

The project search is three pieces. `ProjectSearch` (AbydosKit) walks the tree
and streams `FileSearchResult`s — a file and its `SearchMatch`es, each a UTF-16
range into the file *as it was read* — to `SearchPane` (AbydosApp), which is the
query field, the `Aa`/`W`/`.*` switches, the `✓` toggle, the status line and the
Place control. The list under them is `ResultChecklist`, shared with the usages
pane: it flattens results into `ResultRows`, ticks rows off through
`SearchChecklist`, and keeps one `UndoManager` of its own (`markUndo`) so ⌘Z in
the list takes a tick back rather than an edit somewhere else.

A tick is keyed on a `SearchChecklist.Mark` — the file's relative path, the
matched line's trimmed text, and which of the identical lines in the file it is —
because a line number goes stale the moment anything is inserted above it. That
key already answers the hardest question a project replace has to answer: *which
match is this row, in the file as it is now?*

The find bar replaces one file. `TextSearch.replaceAll` builds one span edit from
the first match to the last, carrying unmatched text through untouched, so two
hundred replacements are one undo entry; `TextSearch.replacement(forMatchAt:)`
re-asserts that the range still matches before it replaces anything;
`TextSearch.isValid(template:)` refuses a `$n` the pattern has no group for,
because Foundation substitutes the empty string and a mistyped digit becomes a
silent deletion of every match. `CodeView.replace(utf16Range:with:)` puts the edit
through `TextDocument.replace`, which records the undo, marks the tab dirty,
schedules the auto-save and tells the find state its matches moved.

A file that is open is reachable as `EditorAreaController.document(for:)`, in
whichever pane holds it. A file that is not open is bytes on disk, and the search
read them as UTF-8 after refusing anything with a NUL in its first eight
kilobytes.

## Goals / Non-Goals

**Goals:**

- Replace, from the search pane, the rows somebody has chosen or every row they
  can see, with the same meaning under the switches the find bar gives a
  replacement, and with the same refusals.
- Edit an open file the way its own find bar would, so the tab is dirty and its
  ⌘Z works; write a closed file only if it still holds what was matched.
- One ⌘Z in the list takes the whole replacement back.
- Say what was done in a number, and never leave the project half-changed with
  nothing said.

**Non-Goals:**

- Replacing in the usages pane. Its rows are a symbol's uses, and the verb for
  "change every use" is a rename through the language server.
- A preview of each file's after-text before the write. The list *is* the
  preview of what will be replaced; what it becomes is the template.
- Replacing in files the search would not read — binaries, non-UTF-8, files past
  `maximumFileSize` — which are never rows and so are never candidates.
- A git safety-net ref before the write. See decision 5.

## Decisions

### 1. The engine re-matches the file as it is now, and chooses by mark

`ProjectReplace` (AbydosKit, beside `ProjectSearch`) is asked, per file: *here is
the text as it is right now, the question, the template, and the marks to
replace — or nil for all of them; give me the one edit.* It runs
`TextSearch.matches` over that text, computes `SearchChecklist.marks(for:)` for
what it finds, keeps the matches whose mark is in the chosen set, and builds a
span edit from the first kept match to the last — unmatched text *and unchosen
matches* carried through untouched. It answers with the edit, how many it
replaced, and which chosen marks it could not find.

*Ruled out: replacing at the ranges the list holds.* Those are offsets into the
file as it was read. A tab that has been typed in since, a file the formatter
touched, a file saved by another program — every one of them moves the offsets,
and an edit at a stale offset replaces the wrong text with no way of knowing it
did. The find bar already refuses this in `replacement(forMatchAt:)`; the project
pane, which cannot see the file, has to refuse it harder.

*Ruled out: one edit per match.* Two hundred replacements in a file would be
two hundred undo entries and two hundred reparses, which `replace-in-file` set
out to never do. `TextSearch.replaceAll` grows a filter rather than being copied.

### 2. Replace is the selection, Replace All is what is showing

The find bar's Replace acts on its current match; the list has no caret, and the
thing the keyboard already moves in it is the selection. So **Replace** replaces
the selected rows — a heading brings every match in its file, folded or not, as
`ResultRows.marks(under:)` already gathers them for a tick — and **Replace All**
replaces every row the list is showing.

Rows the `✓` toggle is hiding are not showing, and Replace All leaves them
alone. A row somebody has ticked and hidden is a row they have put away, and
a button that changed rows nobody could see would be the wrong surprise in the
direction that costs a file.

*Ruled out: Replace All over everything held, hidden or not.* It is the simpler
rule and the more dangerous one, and "what you can see is what changes" is the
rule the rest of the pane already keeps.

*Ruled out: a current-match model.* It would need a caret the list does not
have, and the reason the find bar has one — walking a file with repeated
Replace — is what the checklist's selection and ␣ already do.

### 3. An open file goes through its document; a closed one is written whole

For each file with a kept edit: if `document(for:)` finds it open — in any pane,
dirty or clean — the edit goes through `TextDocument.replace`, so it is one
undo entry in that tab, the tab is dirty, the auto-save is scheduled and the
tab's own find matches move. The text asked of the engine is the document's
rope, not the disk, so a dirty buffer is replaced where its text is.

If the file is not open, the bytes are read again, refused if a NUL is in the
first eight kilobytes or they are not UTF-8 — the search's own tests — and the
edit is applied to the string and written back with `.atomic`. Line endings are
untouched because the edit is a span, not a rewrite.

A read-only document (`TextDocument.replace` refuses one silently) is skipped
and counted with the marks that were not found.

*Ruled out: opening every touched file in a tab and editing there.* Twenty-seven
tabs nobody asked for, and the auto-save would write them to disk a moment
later anyway — it is the disk write with a worse interface in front of it.

*Ruled out: writing to disk and letting the watcher reload the open tab.* The
reload refuses a dirty tab, so a file being edited would silently keep the old
text; and even for a clean tab it throws the tab's undo history away.

### 4. One entry in the list's undo, per-file spans

The replacement registers one action on the checklist's `markUndo` — the
`UndoManager` ⌘Z in the list already reaches — holding, per file, the span's
range and its text before and after. Undoing puts the before-text back, through
the document if the file is open and to disk if not, **only if the span still
reads the after-text**; a file changed since is left as it is, and the status
line says how many were. Redo is the same record the other way.

Marks are not touched by a replace or its undo: a tick says "looked at", and
replacing a row is looking at it.

*Ruled out: whole-file snapshots.* Five hundred files at four megabytes is the
worst case the search permits, and a span is a few hundred bytes.

*Ruled out: the tab's ⌘Z alone.* It covers only the files that were open. The
list's undo covers all of them, and an open file undone from the list is one
more ordinary edit in that tab, which the tab's own history then holds too.

### 5. No safety-net ref

`git-safety` keeps its destructive set small and closed, and every member is a
git operation. A text replacement is an edit, undone as edits are — decision 4
— and a project with no repository needs the same answer. Leaving a ref would
also say "this is dangerous" about a verb the find bar does without one.

*Left open, and cheap to add later:* whether a Replace All that writes to more
than some number of closed files should ask first, leading with the number as
`git-safety` words its dialogs. Not built now; the undo is the answer being
tried first.

### 6. A capped list refuses Replace All

When the walk stopped at a bound — the status line already reads `the first N …
more not shown` — Replace All does nothing and the status line says the query
is too broad to replace all at once. Replace on a selection still works: those
rows are in front of somebody.

*Ruled out: walking the project again, unbounded, for Replace All.* It is what
the in-file Replace All does — every match, not the first `matchLimit` — but a
file is one thing in one buffer and the project is the whole tree: a second
walk would replace matches nobody had seen in files nobody had opened, could
not say its count until it had finished, and a twenty-thousand-match query is
one nobody has narrowed yet. This is the decision most worth revisiting if it
turns out to be asked for.

### 7. ⇧⌘R, and the mode belongs to the pane

*Replace in Project…* in the Edit menu, ⇧⌘R, after *Find in Project…*. It makes
the pane if needed, seeds the query from the selection the way ⇧⌘F does when the
pane was not up, turns replace mode on and puts the keyboard in the replacement
field. ⇧⌘F focuses the query and does not take replace mode away, as ⌘F does not
in the find bar. A `⇄` toggle in the option row, beside `✓`, shows and hides the
row by hand; there is no ⎋-to-close because the pane is not a bar over something.

The mode and the replacement text are the pane's — one per window, like the
query — and survive a project switch with it: the query is a person's words
and so is the replacement.

*Ruled out: ⌥⇧⌘F*, Xcode's key for the same verb, and the first proposal here
because ⇧⌘R was *Review Branch…* in the Agent menu. The maintainer, 2026-09-14:
review is barely used, so the key goes to the verb that pairs with ⇧⌘F the way
⌘R pairs with ⌘F, and *Review Branch…* keeps its menu item with no key
equivalent rather than being given another one nobody asked for.

### 8. What the buttons refuse, and what the status line says

Replace is disabled while nothing is selected. Replace All is disabled while the
list is empty or capped. Both are disabled while the template cannot be used
with the pattern, and the status line says `Replacement cannot be used` in the
place it says `Invalid pattern`. ⏎ in the replacement field is Replace, as in
the find bar.

After a replacement the status line leads with the number — `143 replaced in 27
files`, then `· 3 not found` when rows had gone stale — and the search is run
again so the rows that were replaced leave the list; what the re-run finds
follows in the same line. A replacement that still matches the query brings its
row back, exactly as it does in the find bar, and the leading number is what
says the replacement happened.

Writes happen on the main thread inside `StallWatch.mark("project replace")`,
so the undo record and the list agree at the moment the status is written; a
few dozen span edits is not a stall, and if a run measures one the writes move
to a queue with the status arriving after them.

### 9. Driving

`--search-steps` gains `replacing` (toggle the mode and print it),
`replacement:<text>`, `replace` (the selection) and `replace-all`; `status`
prints `replacing=` and the last replacement's count. Every step is the one a
person takes — the row, the field, the button's own verb — so what a run proves
is the path. A driven run is on a scratch copy under the scratchpad and never
a real checkout, by the house rule every run keeps, and the run's tree step
reads the files back afterwards.

## What was measured, 2026-09-14

Ten driven runs on scratch projects under the session's scratchpad, built as
`de.rnd7.abydos.replace` with an unpinned UUID; a driven run keeps its
preferences in memory, so there was no domain to seed or delete. Load averages
3.5–7.8 across the runs; nothing here is timed. The project: `a.swift` with
three `needle` lines under a line without one, `b.txt` and `notes/c.txt` with
two each, `crlf.txt` with one and CRLF endings, `ids.txt` with `user_id`,
`order_id`, `item_id`.

**Two of eight, by selection** — `select:2+4,replace`:

    SEARCH status: 2 replaced in 2 files · 6 in 4 files … undo=Replace in Project

The two rows were in two files, both written on disk; the six left came back
from the re-run under the count.

**A heading folded shut, a mark, and ⌘Z twice** — row 7 ticked with `␣`,
`click:6` folding `a.swift`, `select:6,replace,undo,redo`:

    SEARCH read a.swift: first line without it⏎needle one⏎needle two⏎needle three⏎   (after ␣)
    SEARCH status: 3 replaced in 1 file · 5 in 3 files
    SEARCH read a.swift: first line without it⏎pin one⏎pin two⏎pin three⏎
    SEARCH status: 3 put back in 1 file · 8 in 4 files · 1 done   redo=Replace in Project
       7 match 2 needle one DONE
    SEARCH status: 3 replaced again in 1 file · 5 in 3 files

`␣` in replace mode ticked and changed no file; the heading took its whole
file and no other; the mark was where it had been after the undo. The `select:7`
had previewed `a.swift` into a tab, so this replacement went through an open
document and the auto-save wrote it — the path decision 3 chose, exercised
without being asked for.

**Hidden done rows under Replace All** — `b.txt`'s two rows ticked, `hide`,
`replace-all`:

    SEARCH status: 6 replaced in 3 files · 2 in 1 file · 2 done
    SEARCH read b.txt: keep⏎needle here⏎keep again⏎needle there⏎
    SEARCH read crlf.txt: line one⏎pin crlf⏎line three⏎

`od -c` on `crlf.txt` afterwards: `\r \n` on every line, as before.

**A dirty tab, and a replacement that matches its own query** — `--file
a.swift --type "extra "`, then `replacement:needle2,replace-all`:

    SEARCH read a.swift: extra first line without it⏎needle2 one⏎needle2 two⏎needle2 three⏎

The typed text was kept and the matches were replaced where they now were; the
edit went through the document and the auto-save wrote it. On a one-file
project, `select:1,tab-key,undo-key` after the same replacement — the ⌘Z
answered by `CodeView` — left the disk at `needle2` and the buffer at:

    | needle one
    | needle two
    | needle three

One ⌘Z in the tab, all three back. The re-run read `3 replaced in 1 file · 3
in 1 file`, the rows back because `needle2` matches `needle`, and the leading
number is what says the replacement happened.

**A capped list** — six files of 5 000 `zz` lines, `--search zz`:

    SEARCH status: the first 20000 in 4 files · more not shown · too broad to replace all at once
        replace-enabled=false replace-all-enabled=false
    SEARCH status: 2 replaced in 1 file · the first 24998 in 5 files · more not shown …

`replace-all` as a step did nothing; `select:1+2,replace` replaced the two.

**⌘Z after a file was edited by hand** — `replace-all`, then from the shell
`pin there` → `PIN there` in `b.txt` during the settle, then `undo`:

    SEARCH status: 8 put back in 3 files · 1 not put back · 6 in 3 files
    SEARCH read b.txt: keep⏎pin here⏎keep again⏎PIN there⏎

`b.txt` was left as the hand had it — the whole file, since its span covered
both matches — and the other three went back.

**A row whose line is gone** — one file, `select:2`, the line deleted from the
shell during the settle, `replace`:

    SEARCH status: 0 replaced · 1 not found · 1 in 1 file
    SEARCH read b.txt: keep⏎needle here⏎keep again⏎

Nothing was written at the old offset. (`0 replaced in 0 files` was what this
first printed, and the second number was dropped.)

**A capture, and a group the pattern has not** — `--search '(\w+)_id'`,
`regex`, `replacement:$7`, then `replacement:$1Id,replace-all`:

    SEARCH status: Replacement cannot be used   replace-enabled=false replace-all-enabled=false
    SEARCH status: 3 replaced in 1 file · No results
    SEARCH read ids.txt: userId⏎orderId⏎itemId⏎

**Where the signature landed.** The pane hands the editor a function of the
text rather than an edit — `editOpenFile(url, (String) -> ReplaceAll?) -> Int`,
answering how many panes had the file open — because a file can be open in two
panes with two documents, and each has to be asked with its own text. `nil`
from the function on an open file is still "open": the disk is not written over
a buffer somebody has. Replace All passes the showing marks rather than `nil`,
so the not-found count means the same thing for both buttons. A file edited
through its document is auto-saved on the spot where the setting allows,
because the re-run that follows reads the disk; the spec's dirty-tab scenario
says so.

## Risks / Trade-offs

- **A replacement that matches its own query** (`foo` → `foobar`) → the rows
  come back on the re-run; the leading `N replaced` is the truth, and a second
  Replace All would replace again. The find bar has the same shape and the same
  answer.
- **A file changed between the search and the replace** → re-matched on its
  current text, so a moved match is still found by its mark and a gone one is
  counted as not found; nothing is written at a stale offset.
- **Two identical lines, one chosen** → the mark's occurrence picks the right
  one; a line inserted above it that is identical to it moves the tick to the
  wrong copy, which `SearchChecklist` already documents as the case it gets
  wrong and accepts.
- **Undo after the file changed** → skipped and said, never a blind overwrite.
- **Case-insensitive search, literal replacement** → every match takes the
  template as typed, which is what `TextSearch.replaceAll` does today.
- **The watcher** → a closed file written to disk changes its git colour in the
  tree through the watcher as any outside write does; nothing new is built.

## Open Questions

- Decision 6 (refuse Replace All on a capped list) and decision 5 (no
  confirmation, no ref) are the two that could be asked for the other way once
  the verb is in use. Both are recorded as the choice tried first.
