# 470. Usages in the bottom panel, as a job somebody works through

Find Usages answers into `UsagesPanel`, a floating `NSPanel` added as a child
window over the code, 760×520 in the middle of the window, with a **Dock** button
that moves it into the *sidebar*. Reported:

> The usages view shall be opened in the bottom view, it should support multi
> selection and manual deletion for progress tracking, it should not only jump to
> the usage on a click but also on keyboard navigation

Which is four things, and three of them already exist one pane away.

## Most of this is `SearchPane`, and that is the point

`SearchPane` is 942 lines of exactly this job — a list of places in files that
somebody opens one at a time, decides about, and moves past. It already has
multi-selection (`allowsMultipleSelection = true`), a per-row done state carried
on the row rather than computed while drawing, file headings that count how many
of their matches are done, a `✓` toggle that hides what is finished, undo, and a
`keyDown` hook on the table.

**So this item is mostly moving usages into the bottom panel and reusing that,
not writing it again.** Where the two lists differ is real but small: a usage
comes from the language server rather than from a text search, so its rows are
`LSPLocation` and its heading is "N usages in M files" rather than a query. If a
common list is the right answer, say so and build it; if the honest thing is a
second pane that shares the checklist and not the view, say that instead. What
must not happen is a third copy of the done logic.

## The word "deletion" is worth one paragraph before anybody writes code

The report says *manual deletion*. `SearchPane`'s doc comment argues at length
for the opposite word, and the argument is good enough that it should be answered
rather than ignored:

> The word is **done**, never "delete", "remove" or "clear". "Mark as Done" and
> "Mark as Not Done" cannot be read as touching the disk, which "Dismiss" —
> halfway between putting a thing aside and getting rid of it — can. […] The key
> is **␣**, which is what ticks a checkbox everywhere in the system, is
> destructive nowhere, and is nowhere near ⌫. ⌫ and ⌘⌫ are deliberately left
> unanswered here: a key that trashes files one pane over must do nothing at all
> in this one.

⌘⌫ in the project tree moves a file to the trash, and both panes are the same
list-shaped thing full of file names. It also argues for keeping the row —
struck through, greyed, in place — because a list that removes rows as they are
ticked moves everything under the pointer on every press, so the next keystroke
lands on something nobody has looked at.

**That reasoning applies here unchanged, so the default should be ␣ and "done".**
But the report asked for deletion, and there is a case for it that search does not
have: usages are transient — nobody comes back to a usage list tomorrow — so
"gone" may genuinely be what somebody wants, and the `✓` toggle already gives
the shortening list without the risk. Decide it, write down which and why, and if
it does become a removal then it needs a keystroke that is *not* ⌫ and a heading
that still says how many there were.

## Opening on keyboard navigation has a cost worth naming

`SearchPane` opens on `table.action` and `doubleAction` — a click, not a
selection change. Opening as the selection moves is the right feature and is what
the report asks for, but held ↓ through two hundred usages would open two hundred
files, and this app keeps a tab per opened file. The usual answer is a transient
or preview tab that is replaced by the next one rather than accumulating, and
whether this app has such a thing — and what it does to the tab bar, to `didOpen`
traffic at the language server, and to the undo stack — is the design question in
this item. Measure the `didOpen`/`didClose` traffic before deciding; the server
is told about every one of them.

Two smaller decisions that follow from it: whether a click and a keystroke should
differ at all, and — the one that is a present-tense bug rather than a risk —
where the keyboard is.

### The keyboard never reaches the list, docked or not

Also from the report:

> and keyboard navigation / cursor when it is docked as well, currently the
> cursor jumps directly to the editor

Two halves, and neither is about the list's own key handling:

- **It is never focused when it appears.** `MainWindowController.dockInSidebar`
  places the view, unhides the container, moves the divider — and calls
  `makeFirstResponder` for nothing. The only two `makeFirstResponder` calls in
  that whole file hand the keyboard to the *terminal*. So the list arrives with
  the keyboard still wherever it was, which is the editor, and ↓ scrolls code.
- **Opening a row takes the keyboard away.** `panel.onOpen` calls
  `editor.open(fileURL:atLine:)`, which focuses the code — so even after
  clicking into the list, the first row somebody opens ends the keyboard
  navigation before it has started. That is what "the cursor jumps directly to
  the editor" is.

So the list has to be focused when it appears and **keep** the keyboard when a row
opens: the editor scrolls and shows the line, and the caret goes there, but first
responder stays in the list so ↓ moves to the next usage. There needs to be a
deliberate way *into* the editor from there — ⏎, or ⇥ — because "look at each of
these" and "now work on this one" are two different intentions and only the second
should cost the keyboard.

Both halves are the same fix for the floating window and the docked pane, which is
an argument for making it once, in whatever holds the list, rather than at each
place that shows it.

## The floating window stays; the default turns around

Both arrangements are wanted, and only the default is wrong. Added to the report
after the first pass:

> maybe I also like the current docked variant, but it should started docked and
> support then the expand to window

So `UsagesPanel.show(locations:over:)` building a child window and putting it in
the middle of the screen is what changes: **usages arrive docked**, and there is a
way from there to a window for somebody who wants one big enough to read. The
`Dock` button becomes its inverse and the flow runs the other way.

Which means the machinery is not thrown away — `onDock` already hands a content
view across to `MainWindowController`, and a view that can move once can move
twice. Two things it does not answer and somebody should:

- **A window that has been expanded, then dismissed — what does the next Find
  Usages do?** Coming back docked when somebody has just chosen a window is an
  answer that will not be believed; remembering the choice means remembering it
  somewhere, and per project is a different feeling from per session.
- **Docked *where*.** The report says the bottom view, and `onDock` today goes to
  the **sidebar** — so "the current docked variant" and "the bottom view" are two
  different places, and this item cannot keep both without becoming three ways to
  show one list. Take the bottom panel, beside search, since that is where the
  checklist this reuses already lives, and say in the item what became of the
  sidebar route.

## What was decided

### One list, shared — `ResultChecklist`

Not "a pane that shares the checklist and not the view". The whole list *is*
shared: the table, the rows, the ticking, the file headings, the `✓`, the undo
and the key handling came out of `SearchPane` into `ResultChecklist`, and both
panes put their own controls above it. Search puts a query field and three
option toggles there; usages puts a heading. Neither owns a line of the ticking.

The reason it could be the whole view and not only the model is that the row
type turned out to be the same one. A usage is a path, a line and the text of
that line, which is a `SearchMatch` in a `FileSearchResult` — the type
`SearchChecklist` already keys its marks on. `UsagesPane` converts `LSPLocation`s
into those, reading each file once, which the old panel did anyway to show the
line. Nothing in `AbydosKit` had to change.

`SearchPane` went from 942 lines to 260, and there is one copy of the done logic
rather than two, let alone three.

### Done, not delete — ␣, and the row stays

`SearchPane`'s argument survives the one thing usages have that search does not.
The word is **done**, the key is **␣**, the row stays struck through, and ⌫ and
⌘⌫ do nothing at all. The report asked for deletion; this is the answer to it:

- The hazard is unchanged and is the whole of the original argument. ⌘⌫ in the
  project tree moves a file to the trash. The usages list is *more* alike than
  the search list is, not less: it is nothing but file names and lines of code,
  it now sits in the same panel as search, and it is reached from a context menu
  in the editor rather than from a search field — so somebody arrives at it
  without having typed anything that would remind them which pane they are in.
- The moving-target objection is unchanged too, and matters more here than in
  search. A list that removes rows as they are ticked moves everything under the
  pointer on every press. In search you are usually deciding row by row; in a
  usage list of 263 you run ␣, ↓, ␣, ↓ down a file, and a list that reflows
  under that is one where the next ␣ lands on something nobody looked at.
- The transience argument for "gone" does not actually need a removal. What it
  wants is a list that empties as the work is done, and the `✓` toggle already
  gives exactly that, reversibly, with no keystroke that is destructive-shaped.
  Turning it on is the shortening list; turning it off is the audit.
- And transience cuts the other way as well. Because the marks are keyed on the
  question — here the definition site of the symbol — asking Find Usages again
  about the same symbol brings the ticks back. That is the normal thing to do
  after fixing one of them, and a list that had *deleted* rows would have
  nothing to bring back.

So no removal; therefore no new keystroke to invent and no "N were here" heading
either. The heading counts what was found and puts the progress beside it:
`263 usages in 41 files · 12 done`.

### Where the keyboard is

Both halves of the present-tense bug were real and are fixed in one place,
`ResultChecklist`, so the window and the panel get it from the same code.

- **Focused when it appears.** `BottomPanel.activate` now calls `focusList()` for
  a usages session, and `expandUsages` does the same for the window. Before this,
  nothing in `MainWindowController` called `makeFirstResponder` for the list at
  all — the only two calls in the file hand the keyboard to the terminal.
- **Keeps the keyboard when a row opens.** `onOpen` carries an `Intent`.
  `.preview` opens with `focusEditor: false` into the provisional tab, so the
  editor scrolls, shows the line and puts the caret there while first responder
  stays in the list; `.commit` is the old behaviour and hands the keyboard over.
- **One deliberate way in**, and it is both ⏎ and ⇥, under one rule written into
  the code: **⏎ does the thing the selection has not already done.** In usages
  the selection already previews, so ⏎ means "now I am going to work on this one"
  and goes into the editor. In search the selection previews nothing, so ⏎ is the
  preview and gives the keyboard straight back — unchanged, and the search spec
  still reads true. ⇥ is the same gesture as ⏎ in usages, and is left alone in
  search where it still walks the key view loop to the query field.

### Opening as the selection moves, and what it costs the server

`isARepeat` is the whole answer. A single ↓ reveals its row at once, because a
preview that arrives 120ms late feels broken. A *repeated* ↓ schedules the reveal
and each further repeat cancels the one before, so a key held down through 263
rows reveals one file: the row it stopped on. Walking deliberately reveals one
file per row you stop on, and re-reveals nothing — a row already showing is not
opened a second time.

The tab side was already solved one pane over and did not need inventing: the
editor has a single **provisional tab**, italic in the tab bar, replaced in place
by the next preview and promoted when it is edited or committed to. It is what
the navigator's single-click and the diff list already use, for this exact
reason. `.preview` asks for it, so 263 usages cost one tab.

**A leak found on the way, and fixed.** Preview replacement in
`EditorViewController.open` called `teardown` on the tab it recycled but never
`LanguageService.closed` — the slot is reused rather than removed, so nothing
went through `removeTab`. Walking a usage list through forty files would have
left forty documents open at a server that had been told about every one of them
and about the end of none. `announceClosed` is now called from both paths.

### What became of the sidebar dock

**Gone.** `dockInSidebar`, `undockFromSidebar`, `placeDockDivider`,
`dockContainer`, `dockedView`, the `sidebarSplit` that existed to hold it and
`DockedPane.swift` are all deleted, as is `Editor/UsagesPanel.swift`. The usages
list was the only thing ever docked there — nothing else in the app called
`dockInSidebar` — so keeping it would have been exactly the third way to show one
list that this item exists to prevent. The sidebar is now the tool and nothing
else, with no split and no divider nobody can reach.

### After an Expand, and where the choice lives

Remembered **per window, in memory, not written to disk**
(`usagesOpenInWindow`). Expand, read it, close the window, ask again: a window.

Per project and `Settings` were both ruled out for the same reason. Wanting a
window is a fact about the current job — *this* symbol has two hundred usages and
the panel is forty rows tall — not a preference about the program, and one Expand
should not decide how Find Usages behaves for the next month. Per project had a
second problem: it would be the only thing in `ProjectSession` that is about a
list nothing restores. Restarting the app is a fresh start and gets the default
back, which is the right amount of memory for something this transient.

Closing the expanded window is *finishing with the list*, not asking for it back
in the panel — the choice of a window stands. **Dock** in the window is how you
ask for it back, and it is the same button as **Expand** with its title turned
around, which is what the item asked for.

## Watched working through a real list

216 usages of `Theme.current.uiFont` in 42 files, from sourcekit-lsp over this
project — the same order of size as 0469's 263, and reachable without going near
the jdtls another agent is holding. Driven with a new `--usages-steps`, which is
`--search-steps`' vocabulary because it is the same list. The machine was under
a load average of 5 to 35 throughout (four other agents building), which is why
everything claimed below is a **count** rather than a duration.

The project was guarded with `--report-open`, which printed
`OPEN project …/abydos-backlog-0470-…` before any step ran.

### It arrives docked, with the keyboard

    USAGES: in window=false panel=true
    USAGES heading: 216 usages in 42 files window=false undo=— redo=— opened=[]
    USAGES who: …ChecklistTable

`panel=true`, `opened=[]`, and the first responder is the list's own table. That
is both halves of the reported bug: before this the list was a floating window
and the keyboard was still in the editor.

### ↓ through it, and what it costs the server

    USAGES traffic: didOpen=2 didClose=1 open=1 tabs=1 [Theme.swift]
    ↓×5   → didOpen=5 didClose=3 open=2 tabs=2 [Theme.swift BreakpointOptionsSheet.swift~]
    ↓×5   → didOpen=6 didClose=4 open=2 tabs=2 [Theme.swift CompletionPopup.swift~]
    ↓ held ×200 → didOpen=7 didClose=5 open=2 tabs=2 [Theme.swift RunningToolsWindowController.swift~]
    ⏎     → didOpen=7 didClose=5 open=2 tabs=2 [Theme.swift RunningToolsWindowController.swift]

The `~` is the provisional tab. Read down that column:

- **210 presses cost 5 `didOpen`s and one tab.** The traffic is one notification
  per *file* the walk crossed, not one per row: five presses that stayed inside
  one file added nothing, because the provisional tab was already showing it.
- **A key held down through 200 rows cost exactly one.** One `didOpen`, one
  reveal — `RunningToolsWindowController.swift:338`, the row it stopped on — and
  the tab count did not move.
- `didClose` tracks `didOpen` one behind, which is the leak this item fixed:
  before it the provisional slot was recycled without ever telling the server,
  and this column would have read `didClose=1` the whole way down while `open`
  climbed to 6.
- Nine reveals for 210 presses, and the last line shows the ⏎: the same file,
  no new notification, and the tab has lost its `~` — the provisional tab
  became a permanent one at the moment somebody committed to it.
- After every ↓ group, `who` was still `ChecklistTable`. After the ⏎ it was
  `CodeView`. That is the whole design in two words.

### The checklist, on this list

    ␣               → 216 usages in 42 files · 1 done   undo=Mark as Done
    ⌫  then ⌘⌫      → 216 usages in 42 files · 1 done   undo=Mark as Done
    ⌘Z              → 216 usages in 42 files            redo=Mark as Done
    ⇧⌘Z             → 216 usages in 42 files · 1 done
    ✓ (hide)        → 216 usages in 42 files · 1 done

⌫ and ⌘⌫ moved nothing and marked nothing, which is the point of choosing ␣. The
heading never lost the count of what was found, including with the done rows
hidden.

Multi-selection, over rows 3, 4 and 5 — a match in one file, the *heading* of the
next file, which has four matches, and the first of those four:

    select 3+4+5, ␣ → · 5 done
    select 0, ␣     → · 6 done
    ✓ (hide)        → 249 rows, and the list now starts at the fourth file

Five and not two: the heading brought its whole file with it, and the match
already inside that file was not counted twice. Then hiding took the three files
that were now entirely done away, headings and all — 258 rows down to 249, which
is six matches and three headings.

### Out to a window and back, and asking again

    ␣                          → · 1 done  window=false
    again                      → · 1 done  window=false
    expand                     → · 1 done  window=true   who=ChecklistTable
    close, again               → · 1 done  window=true    who=ChecklistTable
    …and from the window: dock → · 1 done  window=false   who=ChecklistTable

`again` is a second Find Usages at the same position — a fresh answer from the
server — and the tick came back on it, which is what the marks being keyed on the
symbol rather than on a row position buys. Then: expanded to a window, the window
closed, asked again, and the answer opened **in a window**. Docked again, and the
ticks were still there, because the view moved rather than being rebuilt.

## Ruled out

- **A second pane sharing only the checklist.** The row type is the same type, so
  sharing the whole list was available and sharing less would have meant two
  tables, two key handlers and two sets of cells drifting apart.
- **Removing rows on ␣, or on any other key.** Argued at length above. The `✓`
  toggle already gives the shortening list, so a removal would have bought
  nothing and cost the one thing a list of file names must not have.
- **Adding a field to `SearchChecklist.Question` to keep the two panes' marks
  apart.** Unnecessary: each pane owns its own `SearchChecklist`, so there is no
  shared namespace to collide in and the usages pane can key its questions on
  the definition site with no risk of meeting a search for the same string.
- **`NSApp.currentEvent?.isARepeat` for the held-key case.** It is set by the
  event loop rather than by a press, so nothing driving the table directly could
  be believed about it — and a script that cannot check the claim is a claim
  nobody will check. The flag now comes off the event `ChecklistTable.keyDown`
  received.
- **Revealing from `tableViewSelectionDidChange`.** A click changes the selection
  too, so a click would have previewed *and* committed — opening the same file
  twice. The reveal is driven from `keyDown`, around `super`, by comparing the
  selection before and after.
- **Previewing the first row when the list appears.** The selection lands on the
  first file heading instead. A list that moved the editor before anybody asked
  is worse than one where the first ↓ is the first usage — and landing on the
  first *match* would have meant the first ↓ skipped it.
- **Keeping the sidebar split with one pane in it.** Nothing else was ever docked
  there, so the split, its divider and `DockedPane` went with the route.
- **Timing anything.** Four other agents were building on this machine and the
  load average moved between 5 and 72 while these runs happened. Every number
  above is a count of messages, rows or tabs, all of which mean the same thing on
  a busy machine as on an idle one.
- **A 263-usage Java list from 0469's corpus run.** jdtls on `eclipse.platform.ui`
  is minutes of indexing and is the server item 0452 is working on right now; a
  216-usage Swift list in this project is the same size and did not touch it.
  sourcekit-lsp does need its index warmed first — `references` answers with
  nothing until it has built the package into
  `~/Library/Caches/abydos/index/<project>-<hash>`, which is worth knowing before
  spending twenty minutes wondering why Find Usages is empty.

## Estimate

2026-08-11 15:50 — about two hours left

## Steps

- [x] Decide whether this is one list shared with search or a pane sharing its
      checklist, and say why
- [x] Usages open in the bottom panel, beside search
- [x] Multi-selection, and the done state — with the word and the key decided
      against `SearchPane`'s argument rather than around it
- [x] The list has the keyboard when it appears — nothing calls
      `makeFirstResponder` for it today, docked or floating
- [x] Opening a row keeps the keyboard in the list, with one deliberate way into
      the editor, so ↓ still reaches the next usage
- [x] Opening as the selection moves, without accumulating a tab per usage
- [x] Usages arrive docked, with a way from there to a window — the flow the
      `Dock` button runs today, turned around
- [x] Decide what the next Find Usages does after somebody has expanded one, and
      where that choice is remembered
- [x] Say what becomes of the sidebar dock, since the report's "bottom view" and
      today's docked variant are two different places
- [x] Watch somebody work through a real usage list — the 263-location one from
      0469 is a good size
- [x] Move the `LSPLocation` → `FileSearchResult` conversion into `AbydosKit`,
      so the one part of this with answers that can be wrong has tests
- [x] Tell the language server about the file a recycled provisional tab held —
      found on the way, and this feature would have exercised it hard
- [x] A `--usages-steps` verb, since nothing in the window layer has a test
- [x] Write down here what was ruled out on the way
- [x] `spec/<capability>.md` says what the project now does
